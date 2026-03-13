package com.llfbandit.record.record

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaFormat
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.log10

class PCMReader(
  private val config: RecordConfig,
  private val mediaFormat: MediaFormat,
) : AutoCloseable {
  companion object {
    private val TAG = PCMReader::class.java.simpleName
    private const val DEFAULT_AMPLITUDE_DB = -160.0
    private const val MAX_PCM_VALUE = 32767.0 // 2^15 - 1 for 16-bit signed
  }

  // Reusable buffer
  private val bufferSize: Int = initBufferSize()
  private val readBuffer: ShortArray = ShortArray(bufferSize / 2)

  // Recorder & features
  private val reader: AudioRecord = createReader()
  private var automaticGainControl: AutomaticGainControl? = null
  private var acousticEchoCanceler: AcousticEchoCanceler? = null
  private var noiseSuppressor: NoiseSuppressor? = null

  // Last acquired amplitude (in dB)
  private var amplitudeDb: Double = DEFAULT_AMPLITUDE_DB

  init {
    enableAutomaticGainControl()
    enableEchoSuppressor()
    enableNoiseSuppressor()
  }

  fun start() {
    reader.startRecording()
  }

  fun stop() {
    if (reader.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
      reader.stop()
    }
  }

  @Throws(Exception::class)
  fun read(): ByteArray {
    val readResult = reader.read(readBuffer, 0, readBuffer.size)
    if (readResult < 0) {
      throw Exception(getReadFailureReason(readResult))
    }

    if (readResult > 0) {
      amplitudeDb = calculateAmplitudeDb(readResult)
    }

    return convertToByteArray(readResult)
  }

  fun getAmplitude(): Double = amplitudeDb

  override fun close() {
    release()
  }

  fun release() {
    stop()
    automaticGainControl?.release()
    acousticEchoCanceler?.release()
    noiseSuppressor?.release()
    reader.release()
  }

  @SuppressLint("MissingPermission")
  @Throws(Exception::class)
  private fun createReader(): AudioRecord {
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

    if (config.device != null) {
      if (!reader.setPreferredDevice(config.device)) {
        Log.w(TAG, "Unable to set device: ${config.device.productName}")
      }
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
    return if (mediaFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT) == 1) {
      AudioFormat.CHANNEL_IN_MONO
    } else {
      AudioFormat.CHANNEL_IN_STEREO
    }
  }

  private fun enableAutomaticGainControl() {
    if (AutomaticGainControl.isAvailable()) {
      automaticGainControl = AutomaticGainControl.create(reader.audioSessionId)
      automaticGainControl?.enabled = config.autoGain
    } else if (config.autoGain) {
      Log.d(TAG, "Auto gain effect is not available.")
    }
  }

  private fun enableNoiseSuppressor() {
    if (NoiseSuppressor.isAvailable()) {
      noiseSuppressor = NoiseSuppressor.create(reader.audioSessionId)
      noiseSuppressor?.enabled = config.noiseSuppress
    } else if (config.noiseSuppress) {
      Log.d(TAG, "Noise suppressor effect is not available.")
    }
  }

  private fun enableEchoSuppressor() {
    if (AcousticEchoCanceler.isAvailable()) {
      acousticEchoCanceler = AcousticEchoCanceler.create(reader.audioSessionId)
      acousticEchoCanceler?.enabled = config.echoCancel
    } else if (config.echoCancel) {
      Log.d(TAG, "Echo canceler effect is not available.")
    }
  }

  private fun convertToByteArray(size: Int): ByteArray {
    val byteBuffer = ByteBuffer.allocate(size * 2).order(ByteOrder.LITTLE_ENDIAN)
    for (i in 0 until size) {
      byteBuffer.putShort(readBuffer[i])
    }
    return byteBuffer.array()
  }

  private fun calculateAmplitudeDb(size: Int): Double {
    val max = readBuffer.take(size).maxOf { abs(it.toInt()) }
    return 0.0.coerceAtMost(20 * log10(max / MAX_PCM_VALUE))
  }

  private fun getReadFailureReason(errorCode: Int): String {
    val message = when (errorCode) {
      AudioRecord.ERROR_INVALID_OPERATION -> "ERROR_INVALID_OPERATION: Failure due to improper method use"
      AudioRecord.ERROR_BAD_VALUE -> "ERROR_BAD_VALUE: Invalid value used"
      AudioRecord.ERROR_DEAD_OBJECT -> "ERROR_DEAD_OBJECT: Object no longer valid, needs recreation"
      AudioRecord.ERROR -> "ERROR: Generic operation failure"
      else -> "Unknown error code: $errorCode"
    }
    return "Error when reading audio data: $message"
  }
}