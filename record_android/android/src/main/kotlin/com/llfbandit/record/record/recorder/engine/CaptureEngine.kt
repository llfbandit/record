package com.llfbandit.record.record.recorder.engine

import com.llfbandit.record.record.model.RecordConfig

const val DEFAULT_AMPLITUDE_DB = -160.0

/** Something the engine did on its own initiative; may be raised from any thread. */
sealed interface CaptureEvent {
  class Chunk(val bytes: ByteArray) : CaptureEvent

  /** Capture ended on its own; the engine has already released itself. */
  class Failed(val cause: Throwable) : CaptureEvent
}

/** Runs one recording end to end on the control thread; single-use, done after [stop]. */
interface CaptureEngine {
  /** Starts capturing; returns the effective (possibly renegotiated) config. */
  @Throws(Exception::class)
  fun start(): RecordConfig

  /** @return false if the engine cannot pause right now. */
  fun pause(): Boolean

  fun resume(): Boolean

  /** Releases everything, then answers with the capture or teardown error. */
  fun stop(delete: Boolean, done: (Throwable?) -> Unit)

  /** Latest input level in dB; [DEFAULT_AMPLITUDE_DB] while nothing is captured. */
  val amplitude: Double
}
