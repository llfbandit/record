package com.llfbandit.record.record.recorder

import android.util.Log
import com.llfbandit.record.record.RecordConfig
import com.llfbandit.record.record.RecordState
import com.llfbandit.record.record.stream.RecorderRecordStreamHandler
import com.llfbandit.record.record.stream.RecorderStateStreamHandler

interface OnAudioRecordListener {
    fun onRecord()
    fun onPause()
    fun onStop()
    fun onFailure(ex: Exception)
    fun onAudioChunk(chunk: ByteArray)
}

class AudioRecorder(
    // Recorder streams
    private val recorderStateStreamHandler: RecorderStateStreamHandler,
    private val recorderRecordStreamHandler: RecorderRecordStreamHandler
) : IRecorder, OnAudioRecordListener {
    companion object {
        private val TAG = AudioRecorder::class.java.simpleName
    }

    // Recorder thread with which we will interact
    private var recorderThread: RecordThread? = null
    // Amplitude
    private var maxAmplitude = -160.0
    // Recording config
    private var config: RecordConfig? = null
    // Stop callback to be synchronized between stop method return & record stop
    private var stopCb: ((path: String?) -> Unit)? = null

    @Throws(Exception::class)
    override fun start(config: RecordConfig) {
        this.config = config

        recorderThread = RecordThread(config, this)
        recorderThread!!.startRecording()
    }

    override fun stop(stopCb: ((path: String?) -> Unit)?) {
        this.stopCb = stopCb

        recorderThread?.stopRecording()
    }

    override fun cancel() {
        recorderThread?.cancelRecording()
    }

    override fun pause() {
        recorderThread?.pauseRecording()
    }

    override fun resume() {
        recorderThread?.resumeRecording()
    }

    override val isRecording: Boolean
        get() = recorderThread?.isRecording() == true

    override val isPaused: Boolean
        get() = recorderThread?.isPaused() == true

    override fun getAmplitude(): List<Double> {
        val amplitude = recorderThread?.getAmplitude() ?: -160.0
        val amps: MutableList<Double> = ArrayList()
        amps.add(amplitude)
        amps.add(maxAmplitude)
        return amps
    }

    override fun dispose() {
        stop(null)
    }

    // OnAudioRecordListener
    override fun onRecord() {
        recorderStateStreamHandler.sendStateEvent(RecordState.RECORD.id)
    }

    override fun onPause() {
        recorderStateStreamHandler.sendStateEvent(RecordState.PAUSE.id)
    }

    override fun onStop() {
        stopCb?.invoke(config?.path)
        stopCb = null

        recorderStateStreamHandler.sendStateEvent(RecordState.STOP.id)
    }

    override fun onFailure(ex: Exception) {
        Log.e(TAG, ex.message, ex)
        recorderStateStreamHandler.sendStateErrorEvent(ex)
    }

    override fun onAudioChunk(chunk: ByteArray) {
        recorderRecordStreamHandler.sendRecordChunkEvent(chunk)
    }
}