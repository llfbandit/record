package com.llfbandit.record.record

import android.util.Log
import com.llfbandit.record.record.encoder.EncoderListener
import com.llfbandit.record.record.encoder.IEncoder
import com.llfbandit.record.record.format.AacFormat
import com.llfbandit.record.record.format.AmrNbFormat
import com.llfbandit.record.record.format.AmrWbFormat
import com.llfbandit.record.record.format.FlacFormat
import com.llfbandit.record.record.format.Format
import com.llfbandit.record.record.format.OpusFormat
import com.llfbandit.record.record.format.PcmFormat
import com.llfbandit.record.record.format.WaveFormat
import com.llfbandit.record.record.stream.RecorderRecordStreamHandler
import com.llfbandit.record.record.stream.RecorderStateStreamHandler
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicBoolean

internal interface OnAudioRecordListener {
    fun onRecord()
    fun onPause()
    fun onStop()
    fun onFailure(ex: Exception)
    fun onAudioChunk(chunk: ByteArray)
}

class AudioRecorder(
    // Recording config
    private val config: RecordConfig,
    // Recorder streams
    private val recorderStateStreamHandler: RecorderStateStreamHandler,
    private val recorderRecordStreamHandler: RecorderRecordStreamHandler
) : OnAudioRecordListener {
    private var recorderThread: RecordThread? = null

    // Amplitude
    private var maxAmplitude = -160.0

    /**
     * Starts the recording with the given config.
     */
    @Throws(Exception::class)
    fun start() {
        recorderThread = RecordThread(config)
        recorderThread!!.start()
    }

    /**
     * Stops the recording.
     */
    fun stop() {
        recorderThread?.stopRecording()
    }

    /**
     * Pauses the recording if currently running.
     */
    fun pause() {
        recorderThread?.pauseRecording()
    }

    /**
     * Resumes the recording if currently paused.
     */
    fun resume() {
        recorderThread?.resumeRecording()
    }

    /**
     * Gets the state the of recording
     *
     * @return True if recording. False otherwise.
     */
    val isRecording: Boolean
        get() = recorderThread?.isRecording() == true

    /**
     * Gets the state the of recording
     *
     * @return True if paused. False otherwise.
     */
    val isPaused: Boolean
        get() = recorderThread?.isPaused() == true

    /**
     * Gets the amplitude
     *
     * @return List with current and max amplitude values
     */
    fun getAmplitude(): List<Double> {
        val amplitude = recorderThread?.getAmplitude() ?: -160.0
        val amps: MutableList<Double> = ArrayList()
        amps.add(amplitude)
        amps.add(maxAmplitude)
        return amps
    }

    fun dispose() {
        stop()
    }

    override fun onRecord() {
        updateState(RecordState.RECORD)
    }

    override fun onPause() {
        updateState(RecordState.PAUSE)
    }

    override fun onStop() {
        updateState(RecordState.STOP)
    }

    override fun onFailure(ex: Exception) {
        Log.e(TAG, ex.message, ex)
        recorderStateStreamHandler.sendStateErrorEvent(ex)
    }

    private fun updateState(state: RecordState) {
        recorderStateStreamHandler.sendStateEvent(state.id)
    }

    override fun onAudioChunk(chunk: ByteArray) {
        recorderRecordStreamHandler.sendRecordChunkEvent(chunk)
    }

    private inner class RecordThread(private val config: RecordConfig) : Thread(), EncoderListener {
        private var reader: PCMReader? = null
        private var audioEncoder: IEncoder? = null

        // Signals whether a recording is in progress (true) or not (false).
        private val isRecording = AtomicBoolean(false)

        // Signals whether a recording is paused (true) or not (false).
        private val isPaused = AtomicBoolean(false)

        private val completion = CountDownLatch(1)

        override fun onEncoderDataSize(): Int = reader?.bufferSize ?: 0

        override fun onEncoderDataNeeded(byteBuffer: ByteBuffer): Int {
            if (isPaused()) return 0

            return reader?.read(byteBuffer) ?: 0
        }

        override fun onEncoderFailure(ex: Exception) {
            onFailure(ex)
        }

        override fun onEncoderStream(bytes: ByteArray) {
            onAudioChunk(bytes)
        }

        override fun onEncoderStop() {
            audioEncoder?.release()

            reader?.stop()
            reader?.release()

            updateState(RecordState.STOP)

            completion.countDown()
        }

        fun isRecording(): Boolean {
            return isRecording.get()
        }

        fun isPaused(): Boolean {
            return isPaused.get()
        }

        fun pauseRecording() {
            if (isRecording()) {
                updateState(RecordState.PAUSE)
            }
        }

        fun resumeRecording() {
            if (isPaused()) {
                updateState(RecordState.RECORD)
            }
        }

        fun stopRecording() {
            if (isRecording()) {
                audioEncoder?.stop()
            }
        }

        fun getAmplitude(): Double = reader?.getAmplitude() ?: -160.0

        override fun run() {
            try {
                val format = selectFormat()
                val mediaFormat = format.getMediaFormat(config)

                reader = PCMReader(config, mediaFormat)

                audioEncoder = format.getEncoder(config, this)

                reader?.start()
                audioEncoder?.start()

                updateState(RecordState.RECORD)

                completion.await()
            } catch (ignored: InterruptedException) {
            } catch (ex: Exception) {
                onFailure(ex)
                onEncoderStop()
            }
        }

        private fun selectFormat(): Format {
            when (config.encoder) {
                "aacLc", "aacEld", "aacHe" -> return AacFormat()
                "amrNb" -> return AmrNbFormat()
                "amrWb" -> return AmrWbFormat()
                "flac" -> return FlacFormat()
                "pcm16bit", "pcm8bit" -> return PcmFormat()
                "opus" -> return OpusFormat()
                "wav" -> return WaveFormat()
            }
            throw Exception("Unknown format: " + config.encoder)
        }

        private fun updateState(state: RecordState) {
            when (state) {
                RecordState.PAUSE -> {
                    isRecording.set(true)
                    isPaused.set(true)
                    onPause()
                }

                RecordState.RECORD -> {
                    isRecording.set(true)
                    isPaused.set(false)
                    onRecord()
                }

                RecordState.STOP -> {
                    isRecording.set(false)
                    isPaused.set(false)
                    onStop()
                }
            }
        }
    }

    companion object {
        private val TAG = AudioRecorder::class.java.simpleName
    }
}