package com.llfbandit.record.record.recorder

import android.annotation.SuppressLint
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioRouting
import android.media.MediaFormat
import android.util.Log
import com.llfbandit.record.record.audio_manager.AudioEffectsManager
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.recorder.engine.DEFAULT_AMPLITUDE_DB

/** PCMReader throws this when its device is gone, so the engine reroutes instead of ending the recording. */
class AudioDeadObjectException : Exception(
  "Error when reading audio data: ERROR_DEAD_OBJECT: Object no longer valid, needs recreation"
)

/** [PcmSource] backed by AudioRecord and its audio effects. */
class PCMReader(
  private val config: RecordConfig,
  private val mediaFormat: MediaFormat,
) : PcmSource, AutoCloseable {
  companion object {
    private val TAG = PCMReader::class.java.simpleName
  }

  private val bufferSize: Int = initBufferSize()
  private val buffer = PcmBuffer(bufferSize)
  private var reader: AudioRecord = createReader()
  private var effects = AudioEffectsManager(reader.audioSessionId).also { it.apply(config) }
  private var routingListener: AudioRouting.OnRoutingChangedListener? = null

  // Written by the capture loop, read from the control thread.
  @Volatile
  private var amplitudeDb: Double = DEFAULT_AMPLITUDE_DB

  override fun start(): Boolean {
    if (reader.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
      reader.startRecording()
    }
    return reader.recordingState == AudioRecord.RECORDSTATE_RECORDING
  }

  override fun stop() {
    if (reader.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
      reader.stop()
    }
  }

  @Throws(Exception::class)
  override fun read(): ByteArray {
    val readResult = reader.read(buffer.samples, 0, buffer.samples.size)
    if (readResult < 0) {
      if (readResult == AudioRecord.ERROR_DEAD_OBJECT) throw AudioDeadObjectException()
      throw Exception(getReadFailureReason(readResult))
    }

    if (readResult > 0) {
      amplitudeDb = buffer.amplitudeDb(readResult)
    }

    return buffer.toByteArray(readResult)
  }

  override fun getAmplitude(): Double = amplitudeDb

  override val routedDeviceId: Int? get() = reader.routedDevice?.id

  override fun watchRoute(onChanged: () -> Unit) {
    val listener = AudioRouting.OnRoutingChangedListener { onChanged() }
    routingListener = listener
    // Android may call [onChanged] on any thread, so no handler is needed.
    reader.addOnRoutingChangedListener(listener, null)
  }

  override fun preferDevice(device: AudioDeviceInfo?) {
    reader.setPreferredDevice(device)
  }

  /** Builds the new AudioRecord first, so a failure leaves the current one in place. */
  @Throws(Exception::class)
  override fun recreate(device: AudioDeviceInfo?) {
    val newReader = createReader(device)
    val newEffects = try {
      AudioEffectsManager(newReader.audioSessionId).also { it.apply(config) }
    } catch (e: Exception) {
      newReader.release()
      throw e
    }

    // Release effects before the reader: effects depend on the reader's audio session.
    effects.release()
    releaseReader()
    reader = newReader
    effects = newEffects
    routingListener?.let { newReader.addOnRoutingChangedListener(it, null) }
  }

  override fun close() {
    release()
  }

  override fun release() {
    stop()
    effects.release()
    releaseReader()
    routingListener = null
  }

  private fun releaseReader() {
    routingListener?.let { reader.removeOnRoutingChangedListener(it) }
    reader.release()
  }

  @SuppressLint("MissingPermission")
  @Throws(Exception::class)
  private fun createReader(device: AudioDeviceInfo? = config.device): AudioRecord {
    val sampleRate = mediaFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
    val channels = getChannelsConfig()
    val audioFormat = getAudioFormat()

    val reader = try {
      AudioRecord(
        config.audioSource,
        sampleRate,
        channels,
        audioFormat,
        bufferSize
      )
    } catch (e: IllegalArgumentException) {
      throw Exception("Unable to instantiate PCM reader.", e)
    }

    if (reader.state != AudioRecord.STATE_INITIALIZED) {
      reader.release()
      throw Exception("PCM reader failed to initialize.")
    }

    if (device != null && !reader.setPreferredDevice(device)) {
      Log.w(TAG, "Unable to set device: ${device.productName}")
    }

    return reader
  }

  private fun initBufferSize(): Int {
    val sampleRate = mediaFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
    val channels = getChannelsConfig()
    val audioFormat = getAudioFormat()
    return config.streamBufferSize ?: calculateBufferSize(sampleRate, channels, audioFormat)
  }

  @Throws(Exception::class)
  private fun calculateBufferSize(sampleRate: Int, channelConfig: Int, audioFormat: Int): Int {
    val minBufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)

    return when {
      minBufferSize == AudioRecord.ERROR_BAD_VALUE || minBufferSize == AudioRecord.ERROR -> {
        throw Exception("Recording config is not supported by the hardware, or an invalid config was provided.")
      }

      else -> minBufferSize * 2 // Double the minimum buffer size for safety margin
    }
  }

  private fun getAudioFormat(): Int = AudioFormat.ENCODING_PCM_16BIT

  private fun getChannelsConfig(): Int {
    val numChannels = mediaFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

    return if (numChannels == 1) AudioFormat.CHANNEL_IN_MONO else AudioFormat.CHANNEL_IN_STEREO
  }

  private fun getReadFailureReason(errorCode: Int): String {
    val message = when (errorCode) {
      AudioRecord.ERROR_INVALID_OPERATION -> "ERROR_INVALID_OPERATION: Failure due to improper method use"
      AudioRecord.ERROR_BAD_VALUE -> "ERROR_BAD_VALUE: Invalid value used"
      AudioRecord.ERROR -> "ERROR: Generic operation failure"
      else -> "Unknown error code: $errorCode"
    }
    return "Error when reading audio data: $message"
  }
}