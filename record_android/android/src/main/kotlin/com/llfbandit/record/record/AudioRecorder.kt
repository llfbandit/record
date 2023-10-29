package com.llfbandit.record.record

import android.util.Log
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
) : OnAudioRecordListener {
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

    /**
     * Starts the recording with the given config.
     */
    @Throws(Exception::class)
    fun start(config: RecordConfig) {
        this.config = config

        recorderThread = RecordThread(config, this)
        recorderThread!!.start()
    }

    /**
     * Stops the recording.
     */
    fun stop(stopCb: ((path: String?) -> Unit)?) {
        this.stopCb = stopCb

        recorderThread?.stopRecording()
    }

    /**
     * Stops the recording and delete file.
     */
    fun cancel() {
        recorderThread?.cancelRecording()
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