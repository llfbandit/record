package com.llfbandit.record.record.audio_manager

import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.util.Log
import com.llfbandit.record.record.model.RecordConfig

class AudioEffectsManager(private val audioSessionId: Int) {
  companion object {
    private val TAG = AudioEffectsManager::class.java.simpleName
  }

  private var agc: AutomaticGainControl? = null
  private var aec: AcousticEchoCanceler? = null
  private var ns: NoiseSuppressor? = null

  fun apply(config: RecordConfig) {
    if (AutomaticGainControl.isAvailable()) {
      agc = AutomaticGainControl.create(audioSessionId)
      agc?.enabled = config.autoGain
    } else if (config.autoGain) {
      Log.d(TAG, "Auto gain effect is not available.")
    }

    if (AcousticEchoCanceler.isAvailable()) {
      aec = AcousticEchoCanceler.create(audioSessionId)
      aec?.enabled = config.echoCancel
    } else if (config.echoCancel) {
      Log.d(TAG, "Echo canceler effect is not available.")
    }

    if (NoiseSuppressor.isAvailable()) {
      ns = NoiseSuppressor.create(audioSessionId)
      ns?.enabled = config.noiseSuppress
    } else if (config.noiseSuppress) {
      Log.d(TAG, "Noise suppressor effect is not available.")
    }
  }

  fun release() {
    agc?.release()
    aec?.release()
    ns?.release()
  }
}
