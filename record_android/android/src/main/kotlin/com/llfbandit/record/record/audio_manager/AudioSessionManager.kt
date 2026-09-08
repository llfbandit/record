package com.llfbandit.record.record.audio_manager

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import com.llfbandit.record.record.model.AudioInterruption
import com.llfbandit.record.record.model.RecordConfig

class AudioSessionManager(
  context: Context,
  private val handler: Handler,
  private val onFocusLoss: () -> Unit,
  private val onFocusGain: (AudioInterruption) -> Unit,
) {
  companion object {
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

  private val prevMuteSettings = HashMap<Int, Int>()
  private var prevAudioMode: Int = AudioManager.MODE_NORMAL
  private var prevSpeakerphone = false

  private var focusChangeListener: AudioManager.OnAudioFocusChangeListener? = null
  private var focusRequest: AudioFocusRequest? = null

  @Suppress("DEPRECATION")
  fun save() {
    prevMuteSettings.clear()
    muteStreams.forEach { stream ->
      prevMuteSettings[stream] = audioManager.getStreamVolume(stream)
    }
    prevAudioMode = audioManager.mode
    prevSpeakerphone = audioManager.isSpeakerphoneOn
  }

  @Suppress("DEPRECATION")
  fun apply(config: RecordConfig, requestFocus: Boolean) {
    if (requestFocus && config.audioInterruption != AudioInterruption.NONE) {
      requestAudioFocus(config.audioInterruption)
    }
    if (config.muteAudio) {
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
  fun restore(config: RecordConfig?) {
    abandonAudioFocus()
    val conf = config ?: return
    if (conf.muteAudio) {
      setMuted(false)
    }
    if (conf.audioManagerMode != AudioManager.MODE_NORMAL) {
      audioManager.mode = prevAudioMode
    }
    if (conf.speakerphone) {
      audioManager.isSpeakerphoneOn = prevSpeakerphone
    }
  }

  private fun setMuted(mute: Boolean) {
    muteStreams.forEach { stream ->
      val level = if (mute) AudioManager.ADJUST_MUTE
      else (prevMuteSettings[stream] ?: AudioManager.ADJUST_UNMUTE)
      audioManager.setStreamVolume(stream, level, 0)
    }
  }

  @Suppress("DEPRECATION")
  private fun requestAudioFocus(interruption: AudioInterruption) {
    focusChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
      if (focusChange in setOf(
          AudioManager.AUDIOFOCUS_LOSS,
          AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
          AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK
        )
      ) {
        onFocusLoss()
      } else if (focusChange == AudioManager.AUDIOFOCUS_GAIN) {
        onFocusGain(interruption)
      }
    }

    if (Build.VERSION.SDK_INT >= 26) {
      val audioAttrs = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

      focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
        .setAudioAttributes(audioAttrs)
        .setAcceptsDelayedFocusGain(true)
        .setOnAudioFocusChangeListener(focusChangeListener!!, handler)
        .build()

      audioManager.requestAudioFocus(focusRequest!!)
    } else {
      audioManager.requestAudioFocus(
        focusChangeListener, AudioManager.STREAM_VOICE_CALL, AudioManager.AUDIOFOCUS_GAIN
      )
    }
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
