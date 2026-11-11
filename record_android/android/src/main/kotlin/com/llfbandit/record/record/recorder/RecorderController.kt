package com.llfbandit.record.record.recorder

import android.media.AudioDeviceInfo
import com.llfbandit.record.record.audio_manager.AudioEnvironment
import com.llfbandit.record.record.audio_manager.AudioInterruptionPolicy
import com.llfbandit.record.record.audio_manager.EnvironmentEvent
import com.llfbandit.record.record.audio_manager.PolicyAction
import com.llfbandit.record.record.model.AudioRouteChange
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.model.RecordState
import com.llfbandit.record.record.model.RecordStop
import com.llfbandit.record.record.model.StopReason
import com.llfbandit.record.record.recorder.engine.Bound
import com.llfbandit.record.record.recorder.engine.CaptureEngine
import com.llfbandit.record.record.recorder.engine.DEFAULT_AMPLITUDE_DB
import com.llfbandit.record.record.util.DeviceMapping

/** User-visible output from the recording. */
interface RecorderSink {
  /** Pause and record. A take ends with [onStopped]. */
  fun onState(state: RecordState)
  fun onStopped(stop: RecordStop)
  /** A failure the take survived, or one [onStopped] already reported. */
  fun onError(error: Throwable)
  fun onConfigChanged(config: RecordConfig)
}

class Amplitude(val current: Double, val max: Double)

/** Glue between [CaptureEngine] and [AudioEnvironment]; every entry point runs on the control thread. */
class RecorderController(
  private val environment: AudioEnvironment,
  private val engineFactory: (RecordConfig) -> CaptureEngine,
  private val sink: RecorderSink,
) {
  private class Session(val engine: CaptureEngine, var config: RecordConfig) {
    // Resume pins this device again after a loss, once it returns.
    val requestedDevice = config.device
    var state = RecordState.STOP  // STOP until the engine has started
    var maxAmplitude = DEFAULT_AMPLITUDE_DB
  }

  private var session: Session? = null

  val isRecording: Boolean get() = session?.state?.let { it != RecordState.STOP } == true
  val isPaused: Boolean get() = session?.state == RecordState.PAUSE

  fun start(config: RecordConfig, done: (error: Throwable?) -> Unit) {
    // A live session is finalized first: start() doubles as "next take".
    end(delete = false)

    val s = Session(engineFactory(config), config)
    session = s
    environment.prepare(config) {
      // Stopped or disposed while SCO was connecting.
      if (session !== s) {
        done(null)
        return@prepare
      }

      try {
        val effective = s.engine.start()
        // A missing device fell back to the default one.
        if (effective.isModified(s.config) || s.config.deviceMissing) sink.onConfigChanged(effective)
        s.config = effective
        environment.activate(effective)
        moveTo(s, RecordState.RECORD)
      } catch (e: Exception) {
        end(delete = false)
        done(e)
        return@prepare
      }
      done(null)
    }
  }

  fun pause() {
    val s = session ?: return
    when (s.state) {
      RecordState.STOP -> return
      RecordState.RECORD -> if (!pauseEngine(s)) return
      // Interruption-paused: still hand the session back so a focus regain cannot auto-resume.
      RecordState.PAUSE -> {}
    }
    environment.release(s.config)
    moveTo(s, RecordState.PAUSE)
  }

  /** @return [NoInputDeviceException] when the lost device has no replacement. */
  fun resume(): Throwable? {
    val s = session ?: return null
    if (s.state != RecordState.PAUSE) return null

    val bound = try {
      environment.activate(s.config)
      // After a route loss, capture goes back on the selected device if it returned, or on whatever is there now.
      val device = s.requestedDevice?.let { environment.findDevice(it) }
      s.engine.resume(device)
    } catch (e: Exception) {
      environment.release(s.config)
      return e
    }
    when (bound) {
      Bound.NoInput -> {
        environment.release(s.config)
        return NoInputDeviceException()
      }
      is Bound.Failed -> {
        fail(s, bound.cause)
        return bound.cause
      }
      is Bound.On -> reportDevice(s, bound.device)
      Bound.Resumed -> {}
    }
    moveTo(s, RecordState.RECORD)
    return null
  }

  fun stop(): String? = end(delete = false)

  /** Discards the take and let go of Bluetooth SCO too: nothing is kept for a next take. */
  fun cancel(): String? = endThenDispose(delete = true)

  fun dispose() {
    endThenDispose(delete = false)
  }

  /** Current and peak input level; the floor while nothing is being captured. */
  fun amplitude(): Amplitude {
    val s = session?.takeIf { it.state != RecordState.STOP }
      ?: return Amplitude(DEFAULT_AMPLITUDE_DB, DEFAULT_AMPLITUDE_DB)

    val current = s.engine.amplitude
    s.maxAmplitude = maxOf(s.maxAmplitude, current)
    return Amplitude(current, s.maxAmplitude)
  }

  fun onCaptureFailure(source: CaptureEngine, cause: Throwable) {
    val s = session ?: return
    // Ignore anything from an engine that is no longer the current one.
    if (source !== s.engine) return

    fail(s, cause)
    sink.onError(cause)
  }

  /** Applies config.audioRouteChange once the engine loses its input device. */
  fun onRouteLost(source: CaptureEngine) {
    val s = session ?: return
    if (source !== s.engine) return

    when (s.config.audioRouteChange) {
      // Following must not restart a paused capture: the next resume moves it instead.
      AudioRouteChange.FOLLOW -> if (s.state == RecordState.RECORD) {
        when (val bound = s.engine.captureOn(null)) {
          is Bound.On -> reportDevice(s, bound.device)
          Bound.NoInput -> pause()
          is Bound.Failed -> {
            fail(s, bound.cause)
            sink.onError(bound.cause)
          }
        }
      }

      // Pause like a user pause, so a focus regain cannot resume capture on another device.
      AudioRouteChange.PAUSE -> pause()

      AudioRouteChange.STOP -> end(delete = false, StopReason.ROUTE_CHANGE)
    }
  }

  fun onEnvironmentEvent(event: EnvironmentEvent) {
    val s = session ?: return
    for (action in AudioInterruptionPolicy.react(s.config, event)) {
      when (action) {
        PolicyAction.Pause ->
          if (s.state == RecordState.RECORD && pauseEngine(s)) moveTo(s, RecordState.PAUSE)
        // Nobody awaits this resume: on failure the take stays paused, or ends through onStopped.
        PolicyAction.Resume -> resume()?.let(sink::onError)
      }
    }
  }

  /** Tells Dart which device capture is on after a reroute; null is the default one. */
  private fun reportDevice(s: Session, device: AudioDeviceInfo?) {
    // A re-plug keeps the Dart id, so Dart hears nothing; the config still takes the new device.
    val changed = device?.let(DeviceMapping::deviceId) != s.config.device?.let(DeviceMapping::deviceId)
    s.config = s.config.copy(device = device)
    if (changed) sink.onConfigChanged(s.config)
  }

  /** @return false when the engine did not pause; a failed pause ends the take. */
  private fun pauseEngine(s: Session): Boolean = try {
    s.engine.pause()
  } catch (e: Exception) {
    fail(s, e)
    sink.onError(e)
    false
  }

  private fun fail(s: Session, cause: Throwable) {
    session = null
    endSession(s, reason = StopReason.ERROR, reported = cause)
  }

  private fun endThenDispose(delete: Boolean): String? {
    try {
      return end(delete)
    } finally {
      // Bluetooth must be torn down even if the engine or session failed to stop.
      environment.dispose()
    }
  }

  private fun end(delete: Boolean, reason: StopReason = StopReason.STOP): String? {
    val s = session ?: return null
    // Dropped now, so a next take cannot collide with this one.
    session = null
    // Nothing was written if the engine never started (still connecting SCO).
    val recorded = s.state != RecordState.STOP
    endSession(s, delete, reason)
    return if (recorded) s.config.path else null
  }

  private fun endSession(
    s: Session,
    delete: Boolean = false,
    reason: StopReason = StopReason.STOP,
    reported: Throwable? = null,
  ) {
    val error = s.engine.stop(delete)
    try {
      environment.release(s.config)
    } catch (e: Throwable) {
      sink.onError(e)
    }
    if (s.state != RecordState.STOP) {
      s.state = RecordState.STOP
      val path = if (delete) null else s.config.path
      // A failure the stop ran into still reaches Dart, which onError alone would not.
      val failure = reported ?: error
      sink.onStopped(RecordStop(reason, path, failure?.let { it.message ?: it.toString() }))
    }
    error?.let(sink::onError)
  }

  private fun moveTo(s: Session, state: RecordState) {
    if (s.state == state) return
    s.state = state
    sink.onState(state)
  }
}
