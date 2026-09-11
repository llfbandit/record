package com.llfbandit.record.record.recorder

import com.llfbandit.record.record.audio_manager.AudioEnvironment
import com.llfbandit.record.record.audio_manager.AudioInterruptionPolicy
import com.llfbandit.record.record.audio_manager.EnvironmentEvent
import com.llfbandit.record.record.audio_manager.PolicyAction
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.model.RecordState
import com.llfbandit.record.record.recorder.engine.CaptureEngine
import com.llfbandit.record.record.recorder.engine.DEFAULT_AMPLITUDE_DB

/** User-visible output from the recording. */
interface RecorderSink {
  fun onState(state: RecordState)
  fun onError(error: Throwable)
  fun onConfigChanged(config: RecordConfig)
}

class Amplitude(val current: Double, val max: Double)

/** Glue between [CaptureEngine] and [AudioEnvironment]; every entry point runs on the control thread. */
class RecorderController(
  private val environment: AudioEnvironment,
  private val engineFactory: (RecordConfig) -> CaptureEngine,
  private val sink: RecorderSink,
  // Hops back onto the control thread; engines answer from their own.
  private val post: (() -> Unit) -> Unit,
) {
  private class Session(val engine: CaptureEngine, var config: RecordConfig) {
    var state = RecordState.STOP  // STOP until the engine has started
    var maxAmplitude = DEFAULT_AMPLITUDE_DB
  }

  private var session: Session? = null

  val isRecording: Boolean get() = session?.state?.let { it != RecordState.STOP } == true
  val isPaused: Boolean get() = session?.state == RecordState.PAUSE

  fun start(config: RecordConfig, done: (error: Throwable?) -> Unit) {
    // A live session is finalized first: start() doubles as "next take".
    if (session != null) {
      end(delete = false) { beginTake(config, done) }
      return
    }
    beginTake(config, done)
  }

  private fun beginTake(config: RecordConfig, done: (error: Throwable?) -> Unit) {
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
        if (effective.isModified(s.config)) sink.onConfigChanged(effective)
        s.config = effective
        environment.activate(effective)
        moveTo(s, RecordState.RECORD)
      } catch (e: Exception) {
        session = null
        endSession(s) { done(e) }
        return@prepare
      }
      done(null)
    }
  }

  fun pause() {
    val s = session ?: return
    when (s.state) {
      RecordState.STOP -> return
      RecordState.RECORD -> if (!s.engine.pause()) return
      // Interruption-paused: still hand the session back so a focus regain cannot auto-resume.
      RecordState.PAUSE -> {}
    }
    environment.release(s.config)
    moveTo(s, RecordState.PAUSE)
  }

  fun resume() {
    val s = session ?: return
    if (s.state != RecordState.PAUSE || !s.engine.resume()) return
    environment.activate(s.config)
    moveTo(s, RecordState.RECORD)
  }

  /** Answers with the recorded file path, or null if nothing was recording. */
  fun stop(done: (path: String?) -> Unit) = end(delete = false, done)

  /** Discards the take and let go of Bluetooth SCO too: nothing is kept for a next take. */
  fun cancel(done: (path: String?) -> Unit) = endThenDispose(delete = true, done)

  fun dispose(done: () -> Unit) = endThenDispose(delete = false) { done() }

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

    session = null

    endSession(s, reported = cause) { sink.onError(cause) }
  }

  fun onEnvironmentEvent(event: EnvironmentEvent) {
    val s = session ?: return
    for (action in AudioInterruptionPolicy.react(s.config, event)) {
      when (action) {
        PolicyAction.Pause ->
          if (s.state == RecordState.RECORD && s.engine.pause()) moveTo(s, RecordState.PAUSE)
        PolicyAction.Resume -> resume()
      }
    }
  }

  private fun endThenDispose(delete: Boolean, done: (path: String?) -> Unit) {
    try {
      end(delete) { path ->
        environment.dispose()
        done(path)
      }
    } catch (e: Throwable) {
      // Bluetooth must be torn down even if the engine or session failed to stop.
      environment.dispose()
      throw e
    }
  }

  private fun end(delete: Boolean, done: (path: String?) -> Unit) {
    val s = session
    if (s == null) {
      done(null)
      return
    }
    // Dropped now, so a next take cannot collide with this one.
    session = null
    // Nothing was written if the engine never started (still connecting SCO).
    val recorded = s.state != RecordState.STOP
    endSession(s, delete) { done(if (recorded) s.config.path else null) }
  }

  // The engine answers from its own thread, so hop back before touching state.
  private fun endSession(
    s: Session,
    delete: Boolean = false,
    reported: Throwable? = null,
    done: () -> Unit,
  ) {
    s.engine.stop(delete) { error ->
      post {
        try {
          environment.release(s.config)
        } catch (e: Throwable) {
          sink.onError(e)
        }
        moveTo(s, RecordState.STOP)
        error?.takeIf { it !== reported }?.let(sink::onError)
        done()
      }
    }
  }

  private fun moveTo(s: Session, state: RecordState) {
    if (s.state == state) return
    s.state = state
    sink.onState(state)
  }
}
