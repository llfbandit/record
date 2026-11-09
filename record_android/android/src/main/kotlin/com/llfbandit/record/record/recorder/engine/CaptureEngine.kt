package com.llfbandit.record.record.recorder.engine

import android.media.AudioDeviceInfo
import com.llfbandit.record.record.model.RecordConfig
import kotlin.math.log10

/** Amplitude for silence, and for when nothing is being captured at all. */
const val DEFAULT_AMPLITUDE_DB = -160.0

/** dB of a 16-bit [peak], or [DEFAULT_AMPLITUDE_DB] for silence. */
fun peakToDb(peak: Int): Double {
  if (peak == 0) return DEFAULT_AMPLITUDE_DB
  // Short.MIN_VALUE has no matching positive value, so this could go slightly above 0 dB.
  return 0.0.coerceAtMost(20 * log10(peak / 32767.0))
}

/**
 * Something the engine did on its own initiative; raised on the control thread, never from
 * inside an engine call.
 */
sealed interface CaptureEvent {
  class Chunk(val bytes: ByteArray) : CaptureEvent

  /** Capture ended on its own; the engine has already released itself. */
  class Failed(val cause: Throwable) : CaptureEvent

  /** Once per loss; the next [CaptureEngine.resume] or [CaptureEngine.captureOn] moves capture. */
  data object RouteLost : CaptureEvent
}

sealed interface Bound {
  /** What moving capture answers: it never just runs again where it was. */
  sealed interface Move : Bound

  /** Capture moved; [device] is null when Android ignored the pin. */
  class On(val device: AudioDeviceInfo?) : Move

  /** Capture runs again where it was. */
  data object Resumed : Bound

  data object NoInput : Move

  /** Capture cannot go on; the take ends with [cause]. */
  class Failed(val cause: Throwable) : Move
}

/** Android may not honor the pin; until it names a device, trust it. */
fun boundTo(device: AudioDeviceInfo?, routedId: Int?): AudioDeviceInfo? =
  device?.takeIf { routedId == null || routedId == it.id }

/** Runs one recording end to end on the control thread; single-use, done after [stop]. */
interface CaptureEngine {
  /** Starts capturing; returns the effective (possibly renegotiated) config. */
  @Throws(Exception::class)
  fun start(): RecordConfig

  /**
   * @return false if the engine cannot pause right now.
   * @throws Exception when capture failed; the engine has already released itself.
   */
  fun pause(): Boolean

  /**
   * Restarts a paused capture; after a route loss, moves it to [device] first.
   * @throws IllegalStateException if the engine cannot resume right now.
   */
  fun resume(device: AudioDeviceInfo?): Bound

  fun stop(delete: Boolean): Throwable?

  /** Latest input level in dB; [DEFAULT_AMPLITUDE_DB] while nothing is captured. */
  val amplitude: Double

  /** Moves running capture to [device], or to Android's pick when null. */
  fun captureOn(device: AudioDeviceInfo?): Bound.Move
}
