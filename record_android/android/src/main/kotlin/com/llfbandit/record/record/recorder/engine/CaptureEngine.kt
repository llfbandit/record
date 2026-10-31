package com.llfbandit.record.record.recorder.engine

import android.media.AudioDeviceInfo
import com.llfbandit.record.record.model.RecordConfig

/** Amplitude for silence, and for when nothing is being captured at all. */
const val DEFAULT_AMPLITUDE_DB = -160.0

/** Something the engine did on its own initiative; may be raised from any thread. */
sealed interface CaptureEvent {
  class Chunk(val bytes: ByteArray) : CaptureEvent

  /** Capture ended on its own; the engine has already released itself. */
  class Failed(val cause: Throwable) : CaptureEvent

  /** Waits for a [CaptureEngine.captureOn], pause or stop. */
  data object RouteLost : CaptureEvent
}

sealed interface Bound {
  /** [device] is null when Android ignored the pin. */
  class On(val device: AudioDeviceInfo?) : Bound

  data object NoInput : Bound
}

/** Runs one recording end to end on the control thread; single-use, done after [stop]. */
interface CaptureEngine {
  /** Starts capturing; returns the effective (possibly renegotiated) config. */
  @Throws(Exception::class)
  fun start(): RecordConfig

  /** @return false if the engine cannot pause right now. */
  fun pause(): Boolean

  fun resume(): Boolean

  fun stop(delete: Boolean): Throwable?

  /** Latest input level in dB; [DEFAULT_AMPLITUDE_DB] while nothing is captured. */
  val amplitude: Double

  fun captureOn(device: AudioDeviceInfo?): Bound
}
