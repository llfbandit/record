package com.llfbandit.record.record.audio_manager

import com.llfbandit.record.record.model.RecordConfig

/** A normalized fact about the device audio environment. */
sealed interface EnvironmentEvent {
  data object FocusLost : EnvironmentEvent
  data object FocusRegained : EnvironmentEvent
}

/** Owns audio focus/session and Bluetooth SCO; normalizes focus changes to [EnvironmentEvent]s. */
interface AudioEnvironment {
  /** Wired by the owner to receive normalized focus changes. */
  var onEvent: (EnvironmentEvent) -> Unit

  /** Snapshot the current audio settings and connect Bluetooth SCO if needed. */
  fun prepare(config: RecordConfig, onReady: () -> Unit)

  /** Apply the recording's audio session (focus, mute, mode, speakerphone). Idempotent. */
  fun activate(config: RecordConfig)

  /** Hands the audio session back ([activate] takes it again); Bluetooth SCO stays connected. */
  fun release(config: RecordConfig)

  /** Tear down what outlives recordings (Bluetooth SCO). */
  fun dispose()
}
