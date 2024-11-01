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
    // Config to setup the recording
    private val config: RecordConfig,
    private val mediaFormat: MediaFormat,
) {
    companion object {
        private val TAG = PCMReader::class.java.simpleName
    }

    // Recorder & features
    private val reader: AudioRecord = createReader()
    private var automaticGainControl: AutomaticGainControl? = null
    private var acousticEchoCanceler: AcousticEchoCanceler? = null
    private var noiseSuppressor: NoiseSuppressor? = null

    // Min size of the buffer for writings
    private var bufferSize = 0

    // Last acquired amplitude
    private var amplitude: Double = -160.0

    init {
        enableAutomaticGainControl()
        enableEchoSuppressor()
        enableNoiseSuppressor()
    }

    fun start() {
        reader.startRecording()
    }

    fun stop() {
        try {
            if (reader.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                reader.stop()
            }
        } catch (ex: IllegalStateException) {
            // Mute this exception, this should never happen
        }
    }

    @Throws(Exception::class)
    fun read(): ByteArray {
        val buffer = ByteArray(bufferSize)
        val resultBytes = reader.read(buffer, 0, buffer.size)
        if (resultBytes < 0) {
            throw Exception(getReadFailureReason(resultBytes))
        }

        if (resultBytes > 0) {
            // Update amplitude
            amplitude = getAmplitude(buffer, resultBytes)
        }

        return buffer
    }

    fun getAmplitude(): Double {
        return amplitude
    }

    fun release() {
        reader.release()
        automaticGainControl?.release()
        acousticEchoCanceler?.release()
        noiseSuppressor?.release()
    }

    @SuppressLint("MissingPermission")
    @Throws(Exception::class)
    private fun createReader(): AudioRecord {
        val sampleRate = mediaFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        bufferSize = getMinBufferSize(sampleRate, channels, audioFormat)

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
            throw Exception("PCM reader failed to initialize.")
        }

        if (config.device != null) {
            if (!reader.setPreferredDevice(config.device)) {
                Log.w(TAG, "Unable to set device ${config.device.productName}")
            }
        }

        return reader
    }

    private val audioFormat: Int
        get() {
            return AudioFormat.ENCODING_PCM_16BIT
        }

    private val channels: Int
        get() {
            return if (mediaFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT) == 1) {
                AudioFormat.CHANNEL_IN_MONO
            } else {
                AudioFormat.CHANNEL_IN_STEREO
            }
        }

    @Throws(Exception::class)
    private fun getMinBufferSize(sampleRate: Int, channelConfig: Int, audioFormat: Int): Int {
        // Get min size of the buffer for writings
        val bufferSize = AudioRecord.getMinBufferSize(
            sampleRate,
            channelConfig,
            audioFormat
        )
        if (bufferSize == AudioRecord.ERROR_BAD_VALUE || bufferSize == AudioRecord.ERROR) {
            throw Exception("Recording config is not supported by the hardware, or an invalid config was provided.")
        }

        // Stay away from minimal buffer
        return bufferSize * 2
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

    private fun getReadFailureReason(errorCode: Int): String {
        val str = StringBuilder("Error when reading audio data:").appendLine()

        when (errorCode) {
            AudioRecord.ERROR_INVALID_OPERATION -> str.append("ERROR_INVALID_OPERATION: Failure due to the improper use of a method.")
            AudioRecord.ERROR_BAD_VALUE -> str.append("ERROR_BAD_VALUE: Failure due to the use of an invalid value.")
            AudioRecord.ERROR_DEAD_OBJECT -> str.append("ERROR_DEAD_OBJECT: Object is no longer valid and needs to be recreated.")
            AudioRecord.ERROR -> str.append("ERROR: Generic operation failure")
            else -> str.append("Unknown errorCode: (").append(errorCode).append(")")
        }

        return str.toString()
    }

    // Assuming the input is signed int 16
    private fun getAmplitude(chunk: ByteArray, size: Int): Double {
        var max = -160

        val buf = ShortArray(size / 2)
        ByteBuffer.wrap(chunk, 0, size).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()[buf]

        for (b in buf) {
            val curSample = abs(b.toInt())
            if (curSample > max) {
                max = curSample
            }
        }

        return 20 * log10(max / 32767.0) // 16 signed bits 2^15 - 1
    }
}