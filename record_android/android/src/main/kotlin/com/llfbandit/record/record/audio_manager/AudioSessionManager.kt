package com.llfbandit.record.record.audio_manager

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.llfbandit.record.record.model.AudioInterruption
import com.llfbandit.record.record.model.RecordConfig

class AudioSessionManager(
  context: Context,
  private val handler: Handler,
  private val onFocusLoss: () -> Unit,
  private val onFocusGain: () -> Unit,
) {
  companion object {
    private val TAG = AudioSessionManager::class.java.simpleName
    private val muteStreams = arrayOf(
      AudioManager.STREAM_ALARM,
      AudioManager.STREAM_DTMF,
      AudioManager.STREAM_MUSIC,
      AudioManager.STREAM_NOTIFICATION,
      AudioManager.STREAM_RING,
      AudioManager.STREAM_SYSTEM,
      AudioManager.STREAM_VOICE_CALL,
    )
  }

  private val audioManager: AudioManager =
    context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

  private val mutedVolumes = HashMap<Int, Int>()
  private var prevAudioMode: Int = AudioManager.MODE_NORMAL
  private var prevSpeakerphone = false

  private var focusChangeListener: AudioManager.OnAudioFocusChangeListener? = null
  private var focusRequest: AudioFocusRequest? = null

  // A second restore would clobber app changes made since.
  private var applied = false

  /** Idempotent: a session already holding focus keeps its request. */
  @Suppress("DEPRECATION")
  fun apply(config: RecordConfig) {
    if (!applied) {
      // Snapshot here, so a restore never brings back settings from before a pause.
      prevAudioMode = audioManager.mode
      prevSpeakerphone = audioManager.isSpeakerphoneOn
    }
    // Set first, so restore() also undoes a partial apply.
    applied = true
    if (config.audioInterruption != AudioInterruption.NONE) {
      requestAudioFocus()
    }
    if (config.muteAudio && mutedVolumes.isEmpty()) {
      setMuted(true)
    }
    if (config.audioManagerMode != AudioManager.MODE_NORMAL) {
      audioManager.mode = config.audioManagerMode
    }
    if (config.speakerphone) {
      @Suppress("DEPRECATION")
      audioManager.isSpeakerphoneOn = true
    }
  }

  @Suppress("DEPRECATION")
  fun restore(config: RecordConfig) {
    if (!applied) return
    applied = false
    abandonAudioFocus()
    if (config.muteAudio) {
      setMuted(false)
    }
    if (config.audioManagerMode != AudioManager.MODE_NORMAL) {
      audioManager.mode = prevAudioMode
    }
    if (config.speakerphone) {
      audioManager.isSpeakerphoneOn = prevSpeakerphone
    }
  }

  // Volume 0, not ADJUST_MUTE: Android ignores a mute on streams like the alarm.
  private fun setMuted(mute: Boolean) {
    if (mute) {
      // Read all first: some streams share a volume.
      val volumes = muteStreams.associateWith { audioManager.getStreamVolume(it) }
      volumes.forEach { (stream, volume) ->
        if (setVolume(stream, 0)) mutedVolumes[stream] = volume
      }
    } else {
      // Fixed order: DTMF shares another stream's volume, restored after it.
      muteStreams.forEach { stream -> mutedVolumes[stream]?.let { setVolume(stream, it) } }
      mutedVolumes.clear()
    }
  }

  private fun setVolume(stream: Int, volume: Int): Boolean = try {
    audioManager.setStreamVolume(stream, volume, 0)
    true
  } catch (e: SecurityException) {
    // DND without policy access; best effort.
    Log.w(TAG, "Cannot change volume of stream $stream: ${e.message}")
    false
  }

  @Suppress("DEPRECATION")
  private fun requestAudioFocus() {
    if (focusChangeListener != null) return

    // Pre-26 delivers on the main thread; bounce over and drop events from a replaced request.
    lateinit var listener: AudioManager.OnAudioFocusChangeListener
    listener = AudioManager.OnAudioFocusChangeListener { focusChange ->
      runOnControlThread {
        if (focusChangeListener !== listener) return@runOnControlThread

        when (focusChange) {
          AudioManager.AUDIOFOCUS_LOSS -> {
            // Permanent: the framework dropped our request; forget it so apply() asks again.
            abandonAudioFocus()
            onFocusLoss()
          }

          AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
          AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> onFocusLoss()

          AudioManager.AUDIOFOCUS_GAIN -> onFocusGain()
        }
      }
    }
    focusChangeListener = listener

    val result = if (Build.VERSION.SDK_INT >= 26) {
      val audioAttrs = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

      focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
        .setAudioAttributes(audioAttrs)
        .setAcceptsDelayedFocusGain(true)
        .setOnAudioFocusChangeListener(listener, handler)
        .build()

      audioManager.requestAudioFocus(focusRequest!!)
    } else {
      audioManager.requestAudioFocus(
        listener, AudioManager.STREAM_VOICE_CALL, AudioManager.AUDIOFOCUS_GAIN
      )
    }

    if (result == AudioManager.AUDIOFOCUS_REQUEST_FAILED) {
      Log.w(TAG, "Audio focus refused; the next activate() will ask again.")
      abandonAudioFocus()
    }
  }

  private fun runOnControlThread(block: () -> Unit) {
    if (Looper.myLooper() === handler.looper) block() else handler.post(block)
  }

  @Suppress("DEPRECATION")
  private fun abandonAudioFocus() {
    if (Build.VERSION.SDK_INT >= 26) {
      if (focusRequest != null) {
        audioManager.abandonAudioFocusRequest(focusRequest!!)
        focusRequest = null
      }
    } else if (focusChangeListener != null) {
      audioManager.abandonAudioFocus(focusChangeListener)
    }
    focusChangeListener = null
  }
}
