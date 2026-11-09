package com.llfbandit.record.record.recorder

import android.annotation.SuppressLint
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioRouting
import android.media.MediaFormat
import android.os.Handler
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
) : PcmSource {
  companion object {
    private val TAG = PCMReader::class.java.simpleName

    // The hardware needs a moment to switch to the device that replaces the lost one.
    private const val MAX_REBUILD_ATTEMPTS = 3
    private const val REBUILD_RETRY_DELAY_MS = 150L
  }

  private val minBufferSize: Int = minBufferSize()
  // One chunk is what each read hands over.
  private val buffer = PcmBuffer(chunkSize())
  // Samples of the current chunk read so far.
  private var filled = 0
  private val bufferSize = minBufferSize * 4
  private var reader: AudioRecord = createReader()
  private var effects = try {
    AudioEffectsManager(reader.audioSessionId).also { it.apply(config) }
  } catch (e: Exception) {
    reader.release()
    throw e
  }
  private var routingListener: AudioRouting.OnRoutingChangedListener? = null
  private var routingHandler: Handler? = null

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
    val size = buffer.samples.size
    val readResult = reader.read(buffer.samples, filled, size - filled, AudioRecord.READ_NON_BLOCKING)
    if (readResult < 0) {
      if (readResult == AudioRecord.ERROR_DEAD_OBJECT) throw AudioDeadObjectException()
      throw Exception(getReadFailureReason(readResult))
    }

    filled += readResult
    if (filled < size) return ByteArray(0)

    filled = 0
    amplitudeDb = buffer.amplitudeDb()
    return buffer.toByteArray()
  }

  override fun flush(): ByteArray {
    if (filled == 0) return ByteArray(0)
    val bytes = buffer.toByteArray(filled)
    filled = 0
    return bytes
  }

  override fun getAmplitude(): Double = amplitudeDb

  override val routedDevice: AudioDeviceInfo? get() = reader.routedDevice

  override fun watchRoute(handler: Handler, onChanged: () -> Unit) {
    val listener = AudioRouting.OnRoutingChangedListener { onChanged() }
    routingListener = listener
    routingHandler = handler
    reader.addOnRoutingChangedListener(listener, handler)
  }

  override fun preferDevice(device: AudioDeviceInfo?) {
    reader.setPreferredDevice(device)
  }

  /** Builds the new AudioRecord first, so a failure leaves the current one in place. */
  @Throws(Exception::class)
  override fun recreate(device: AudioDeviceInfo?) {
    val newReader = createReaderRetrying(device)
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
    routingListener?.let { newReader.addOnRoutingChangedListener(it, routingHandler) }
  }

  override fun release() {
    stop()
    effects.release()
    releaseReader()
    routingListener = null
    routingHandler = null
  }

  private fun createReaderRetrying(device: AudioDeviceInfo?): AudioRecord {
    var attempt = 1
    while (true) {
      try {
        return createReader(device)
      } catch (e: Exception) {
        // The replacement device may not be there yet.
        if (attempt++ == MAX_REBUILD_ATTEMPTS) throw e
        Thread.sleep(REBUILD_RETRY_DELAY_MS)
      }
    }
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

  @Throws(Exception::class)
  private fun minBufferSize(): Int {
    val sampleRate = mediaFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
    val size = AudioRecord.getMinBufferSize(sampleRate, getChannelsConfig(), getAudioFormat())
    if (size == AudioRecord.ERROR_BAD_VALUE || size == AudioRecord.ERROR) {
      throw Exception("Recording config is not supported by the hardware, or an invalid config was provided.")
    }
    return size
  }

  // Whole frames only: AudioRecord never reads part of one, so a partial frame would stall the chunk.
  private fun chunkSize(): Int {
    val size = config.streamBufferSize ?: return minBufferSize * 2
    val frameSize = if (getChannelsConfig() == AudioFormat.CHANNEL_IN_MONO) 2 else 4
    require(size >= frameSize) { "streamBufferSize must be at least $frameSize bytes." }
    return size - size % frameSize
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