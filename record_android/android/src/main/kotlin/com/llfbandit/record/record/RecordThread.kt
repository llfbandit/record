package com.llfbandit.record.record

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
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicBoolean

class RecordThread(
    private val config: RecordConfig,
    private val recorderListener: OnAudioRecordListener
) : Thread(), EncoderListener {
    private var reader: PCMReader? = null
    private var audioEncoder: IEncoder? = null

    // Signals whether a recording is in progress (true) or not (false).
    private val isRecording = AtomicBoolean(false)

    // Signals whether a recording is paused (true) or not (false).
    private val isPaused = AtomicBoolean(false)
    private var hasBeenCanceled = false

    private val completion = CountDownLatch(1)

    override fun onEncoderDataSize(): Int = reader?.bufferSize ?: 0

    override fun onEncoderDataNeeded(byteBuffer: ByteBuffer): Int {
        if (isPaused()) return 0

        return reader?.read(byteBuffer) ?: 0
    }

    override fun onEncoderFailure(ex: Exception) {
        recorderListener.onFailure(ex)
    }

    override fun onEncoderStream(bytes: ByteArray) {
        recorderListener.onAudioChunk(bytes)
    }

    override fun onEncoderStop() {
        audioEncoder?.release()

        reader?.stop()
        reader?.release()

        if (hasBeenCanceled) {
            deleteFile()
        }

        updateState(RecordState.STOP)

        completion.countDown()
    }

    fun isRecording(): Boolean {
        return audioEncoder != null && isRecording.get()
    }

    fun isPaused(): Boolean {
        return audioEncoder != null && isPaused.get()
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

    fun cancelRecording() {
        if (isRecording()) {
            hasBeenCanceled = true
            audioEncoder?.stop()
        } else {
            deleteFile()
        }
    }

    fun getAmplitude(): Double = reader?.getAmplitude() ?: -160.0

    override fun run() {
        try {
            val format = selectFormat()
            val mediaFormat = format.getMediaFormat(config)

            reader = PCMReader(config, mediaFormat)

            audioEncoder = format.getEncoder(config, this)

            reader!!.start()
            audioEncoder!!.start()

            updateState(RecordState.RECORD)

            completion.await()
        } catch (ignored: InterruptedException) {
        } catch (ex: Exception) {
            recorderListener.onFailure(ex)
            onEncoderStop()
        }
    }

    private fun selectFormat(): Format {
        when (config.encoder) {
            AudioEncoder.aacLc, AudioEncoder.aacEld, AudioEncoder.aacHe -> return AacFormat()
            AudioEncoder.amrNb -> return AmrNbFormat()
            AudioEncoder.amrWb -> return AmrWbFormat()
            AudioEncoder.flac -> return FlacFormat()
            AudioEncoder.pcm16bits -> return PcmFormat()
            AudioEncoder.opus -> return OpusFormat()
            AudioEncoder.wav -> return WaveFormat()
        }
        throw Exception("Unknown format: " + config.encoder)
    }

    private fun updateState(state: RecordState) {
        when (state) {
            RecordState.PAUSE -> {
                isRecording.set(true)
                isPaused.set(true)
                recorderListener.onPause()
            }

            RecordState.RECORD -> {
                isRecording.set(true)
                isPaused.set(false)
                recorderListener.onRecord()
            }

            RecordState.STOP -> {
                isRecording.set(false)
                isPaused.set(false)
                recorderListener.onStop()
            }
        }
    }

    private fun deleteFile() {
        val path = config.path

        if (path != null) {
            val file = File(path)

            if (file.exists()) {
                file.delete()
            }
        }
    }
}