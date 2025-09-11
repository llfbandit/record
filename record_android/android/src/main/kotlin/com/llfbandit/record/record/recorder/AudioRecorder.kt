package com.llfbandit.record.record.recorder

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.llfbandit.record.record.AudioInterruption
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
    private const val DEFAULT_AMPLITUDE = -160.0
  }

  // Recorder thread with which we will interact
  private var recorderThread: RecordThread? = null

  // Amplitude
  private var maxAmplitude = DEFAULT_AMPLITUDE

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

  private var afChangeListener: AudioManager.OnAudioFocusChangeListener? = null
  private var afRequest: AudioFocusRequest? = null

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

    if (recorderThread != null) {
      if (recorderThread?.isRecording() ?: false) {
        recorderThread?.stopRecording()
      } else {
        onStop()
      }
    } else {
      onStop()
    }
  }

  override fun cancel() {
    recorderThread?.cancelRecording()
  }

  override fun pause() {
    if (isRecording) {
      restoreAudioManagerSettings()
    }

    recorderThread?.pauseRecording()
  }

  override fun resume() {
    if (isPaused) {
      assignAudioManagerSettings(config)
    }

    recorderThread?.resumeRecording()
  }

  override val isRecording: Boolean
    get() = recorderThread?.isRecording() == true

  override val isPaused: Boolean
    get() = recorderThread?.isPaused() == true

  override fun getAmplitude(): List<Double> {
    val amplitude = recorderThread?.getAmplitude() ?: DEFAULT_AMPLITUDE
    if (amplitude > maxAmplitude) {
      maxAmplitude = amplitude
    }

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

    maxAmplitude = DEFAULT_AMPLITUDE
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
  private fun assignAudioManagerSettings(config: RecordConfig?) {
    val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    requestAudioFocus(audioManager)

    val conf = config ?: return

    if (conf.muteAudio) {
      muteAudio(audioManager, true)
    }
    if (conf.audioManagerMode != AudioManager.MODE_NORMAL) {
      audioManager.mode = conf.audioManagerMode
    }
    if (conf.speakerphone) {
      audioManager.isSpeakerphoneOn = true
    }
  }

  // Restore initial audio manager settings
  @Suppress("DEPRECATION")
  private fun restoreAudioManagerSettings() {
    val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    abandonAudioFocus(audioManager)

    val conf = config ?: return

    if (conf.muteAudio) {
      muteAudio(audioManager, false)
    }
    if (conf.audioManagerMode != AudioManager.MODE_NORMAL) {
      audioManager.mode = amPrevAudioMode
    }
    if (conf.speakerphone) {
      audioManager.isSpeakerphoneOn = amPrevSpeakerphone
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

  @Suppress("DEPRECATION")
  private fun requestAudioFocus(audioManager: AudioManager) {
    afChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
      if (focusChange == AudioManager.AUDIOFOCUS_LOSS) {
        if (config!!.audioInterruption != AudioInterruption.NONE) {
          recorderThread?.pauseRecording()
        }
      } else if (focusChange == AudioManager.AUDIOFOCUS_GAIN) {
        if (config!!.audioInterruption == AudioInterruption.PAUSE_RESUME) {
          recorderThread?.resumeRecording()
        }
      }
    }

    if (Build.VERSION.SDK_INT >= 26) {
      afRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN).run {
        setAudioAttributes(AudioAttributes.Builder().run {
          setUsage(AudioAttributes.USAGE_MEDIA)
          setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
          build()
        })
        setOnAudioFocusChangeListener(afChangeListener!!, Handler(Looper.getMainLooper()))
        build()
      }

      audioManager.requestAudioFocus(afRequest!!)
    } else {
      audioManager.requestAudioFocus(
        afChangeListener, AudioManager.STREAM_VOICE_CALL, AudioManager.AUDIOFOCUS_GAIN
      )
    }
  }

  @Suppress("DEPRECATION")
  private fun abandonAudioFocus(audioManager: AudioManager) {
    if (Build.VERSION.SDK_INT >= 26) {
      if (afRequest != null) {
        audioManager.abandonAudioFocusRequest(afRequest!!)
        afRequest = null
      }
    } else if (afChangeListener != null) {
      audioManager.abandonAudioFocus(afChangeListener)
    }

    afChangeListener = null
  }
}