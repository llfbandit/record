package com.llfbandit.record.record.audio_manager

import com.llfbandit.record.record.model.AudioInterruption
import com.llfbandit.record.record.model.RecordConfig

enum class PolicyAction { Pause, Resume }

/** The single home for what `audioInterruption` means. */
object AudioInterruptionPolicy {
  fun react(config: RecordConfig, event: EnvironmentEvent): List<PolicyAction> = when (event) {
    EnvironmentEvent.FocusLost ->
      if (config.audioInterruption != AudioInterruption.NONE) listOf(PolicyAction.Pause)
      else emptyList()

    EnvironmentEvent.FocusRegained ->
      if (config.audioInterruption == AudioInterruption.PAUSE_RESUME) listOf(PolicyAction.Resume)
      else emptyList()
  }
}
