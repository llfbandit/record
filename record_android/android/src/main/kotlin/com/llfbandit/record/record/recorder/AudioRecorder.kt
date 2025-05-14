package com.llfbandit.record.record.recorder

import android.content.Context
import android.media.AudioManager
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
    private val recorderRecordStreamHandler: RecorderRecordStreamHandler,
    private val appContext: Context
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

    // Audio manager settings saved/restored
    private var amPrevMuteSettings = HashMap<Int, Int>()
    private val muteStreams = arrayOf(
        AudioManager.STREAM_ALARM,
        AudioManager.STREAM_DTMF,
        AudioManager.STREAM_MUSIC,
        AudioManager.STREAM_NOTIFICATION,
        AudioManager.STREAM_RING,
        AudioManager.STREAM_SYSTEM,
        AudioManager.STREAM_VOICE_CALL,
    )
    private var amPrevAudioMode: Int = AudioManager.MODE_NORMAL
    private var amPrevSpeakerphone = false

    init {
        saveAudioManagerSettings()
    }

    /**
     * Starts the recording with the given config.
     */
    @Throws(Exception::class)
    override fun start(config: RecordConfig) {
        this.config = config

        recorderThread = RecordThread(config, this)
        recorderThread!!.startRecording()

        assignAudioManagerSettings(config)
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
        recorderStateStreamHandler.sendStateEvent(RecordState.RECORD)
    }

    override fun onPause() {
        recorderStateStreamHandler.sendStateEvent(RecordState.PAUSE)
    }

    override fun onStop() {
        // Restore audio manager properties
        restoreAudioManagerSettings()

        stopCb?.invoke(config?.path)
        stopCb = null

        recorderStateStreamHandler.sendStateEvent(RecordState.STOP)
    }

    override fun onFailure(ex: Exception) {
        Log.e(TAG, ex.message, ex)
        recorderStateStreamHandler.sendStateErrorEvent(ex)
    }

    override fun onAudioChunk(chunk: ByteArray) {
        recorderRecordStreamHandler.sendRecordChunkEvent(chunk)
    }

    // Save initial audio manager settings
    @Suppress("DEPRECATION")
    private fun saveAudioManagerSettings() {
        amPrevMuteSettings.clear()

        val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        muteStreams.forEach { stream ->
            amPrevMuteSettings[stream] = audioManager.getStreamVolume(stream)
        }

        amPrevAudioMode = audioManager.mode
        amPrevSpeakerphone = audioManager.isSpeakerphoneOn
    }

    // Assign audio manager settings
    @Suppress("DEPRECATION")
    private fun assignAudioManagerSettings(config: RecordConfig) {
        val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        if (config.muteAudio) {
            muteAudio(audioManager, true)
        }
        if (config.audioManagerMode != AudioManager.MODE_NORMAL) {
            audioManager.mode = config.audioManagerMode
        }
        if (config.speakerphone) {
            audioManager.setSpeakerphoneOn(true)
        }
    }

    // Restore initial audio manager settings
    @Suppress("DEPRECATION")
    private fun restoreAudioManagerSettings() {
        val conf = config ?: return

        val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        if (conf.muteAudio) {
            muteAudio(audioManager, false)
        }
        if (conf.audioManagerMode != AudioManager.MODE_NORMAL) {
            audioManager.mode = amPrevAudioMode
        }
        if (conf.speakerphone) {
            audioManager.setSpeakerphoneOn(amPrevSpeakerphone)
        }
    }

    private fun muteAudio(audioManager: AudioManager, mute: Boolean) {
        val muteValue = AudioManager.ADJUST_MUTE
        val unmuteValue = AudioManager.ADJUST_UNMUTE

        muteStreams.forEach { stream ->
            val volumeLevel = if (mute) muteValue else (amPrevMuteSettings[stream] ?: unmuteValue)
            audioManager.setStreamVolume(stream, volumeLevel, 0)
        }
    }
}