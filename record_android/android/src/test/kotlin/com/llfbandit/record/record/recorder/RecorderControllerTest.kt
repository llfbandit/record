package com.llfbandit.record.record.recorder

import com.llfbandit.record.record.audio_manager.AudioEnvironment
import com.llfbandit.record.record.audio_manager.EnvironmentEvent
import com.llfbandit.record.record.model.AudioInterruption
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.model.RecordState
import com.llfbandit.record.record.recorder.engine.CaptureEngine
import com.llfbandit.record.record.recorder.engine.DEFAULT_AMPLITUDE_DB
import com.llfbandit.record.testRecordConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RecorderControllerTest {
  private val env = FakeAudioEnvironment()
  private val engine = FakeCaptureEngine()
  private val sink = CapturingSink()
  // Inline: the fakes answer on the calling thread.
  private val controller =
    RecorderController(env, { engine.also { e -> e.config = it } }, sink, { it() })

  private val config = testRecordConfig()

  private fun startRecording(cfg: RecordConfig = config) {
    controller.start(cfg) {}
    assertEquals(RecordState.RECORD, sink.states.last())
  }

  private fun stop(): String? {
    var path: String? = null
    var answered = false
    controller.stop { p -> path = p; answered = true }
    assertTrue("stop must answer", answered)
    return path
  }

  private fun cancel() = controller.cancel {}

  private fun dispose() = controller.dispose {}

  // --- start ---

  @Test
  fun `start prepares, starts the engine, activates the session and broadcasts RECORD`() {
    val probe = DoneProbe()
    controller.start(config, probe.done)

    assertEquals(listOf("prepare", "activate"), env.calls)
    assertEquals(listOf("start"), engine.calls)
    assertEquals(listOf(RecordState.RECORD), sink.states)
    assertTrue(controller.isRecording)
    assertEquals(1, probe.calls)
    assertNull(probe.error)
  }

  @Test
  fun `start waits for the environment before touching the engine`() {
    env.deferPrepare = true
    val probe = DoneProbe()
    controller.start(config, probe.done)

    assertTrue(engine.calls.isEmpty())
    assertEquals(0, probe.calls)
    assertFalse(controller.isRecording)

    env.completePrepare()
    assertEquals(listOf("start"), engine.calls)
    assertEquals(1, probe.calls)
  }

  @Test
  fun `a failed engine start answers with the error and leaves the stream quiet`() {
    engine.startError = RuntimeException("mic busy")
    val probe = DoneProbe()
    controller.start(config, probe.done)

    assertEquals(1, probe.calls)
    assertEquals("mic busy", probe.error?.message)
    assertTrue(sink.errors.isEmpty())
    assertTrue(sink.states.isEmpty())
    assertEquals(listOf("prepare", "release"), env.calls)
    assertFalse(controller.isRecording)
  }

  @Test
  fun `a failed session activation stops the engine and answers with the error`() {
    env.activateError = SecurityException("dnd")
    val probe = DoneProbe()
    controller.start(config, probe.done)

    assertEquals(listOf("start", "stop"), engine.calls)
    assertEquals(listOf("prepare", "activate", "release"), env.calls)
    assertEquals(1, probe.calls)
    assertEquals("dnd", probe.error?.message)
    assertTrue(sink.states.isEmpty())
    assertFalse(controller.isRecording)
  }

  @Test
  fun `start while recording finalizes the current take and starts the next`() {
    startRecording()
    val probe = DoneProbe()
    controller.start(testRecordConfig(path = "/tmp/other.wav"), probe.done)

    assertEquals(listOf("start", "stop", "start"), engine.calls)
    assertEquals(false, engine.deleteRequested)
    assertEquals(
      listOf(RecordState.RECORD, RecordState.STOP, RecordState.RECORD),
      sink.states,
    )
    assertEquals(1, probe.calls)
    assertNull(probe.error)
    assertEquals("/tmp/other.wav", stop())
  }

  @Test
  fun `a stop during SCO connect supersedes the start without launching the engine`() {
    env.deferPrepare = true
    val probe = DoneProbe()
    controller.start(config, probe.done)

    assertNull("no file was recorded", stop())
    env.completePrepare()     // SCO finally reports ready

    assertEquals(listOf("stop"), engine.calls)
    assertTrue("release" in env.calls)
    assertEquals(1, probe.calls)
    assertNull(probe.error)
    assertTrue("never left STOP", sink.states.isEmpty())
    assertFalse(controller.isRecording)
  }

  @Test
  fun `a renegotiated config is reported and becomes the active config`() {
    engine.effectiveConfig = testRecordConfig(path = config.path, sampleRate = 16000)
    startRecording()

    assertEquals(listOf(16000), sink.configChanges.map { it.sampleRate })
    assertEquals(config.path, stop())
  }

  @Test
  fun `an unchanged effective config is not reported`() {
    startRecording()
    assertTrue(sink.configChanges.isEmpty())
  }

  // --- pause / resume ---

  @Test
  fun `a user pause hands the session back and broadcasts PAUSE`() {
    startRecording()
    env.calls.clear()

    controller.pause()

    assertEquals(listOf("pause"), engine.calls.drop(1))
    assertEquals(listOf("release"), env.calls)
    assertEquals(RecordState.PAUSE, sink.states.last())
    assertTrue(controller.isPaused)
  }

  @Test
  fun `a pause the engine cannot honor changes nothing`() {
    engine.canPause = false
    startRecording()
    env.calls.clear()

    controller.pause()

    assertTrue(env.calls.isEmpty())
    assertEquals(RecordState.RECORD, sink.states.last())
    assertFalse(controller.isPaused)
  }

  @Test
  fun `a user resume takes the session again and broadcasts RECORD`() {
    startRecording()
    controller.pause()
    env.calls.clear()
    engine.calls.clear()

    controller.resume()

    assertEquals(listOf("resume"), engine.calls)
    assertEquals(listOf("activate"), env.calls)
    assertEquals(RecordState.RECORD, sink.states.last())
  }

  @Test
  fun `pause and resume outside their state never reach the engine`() {
    controller.pause()
    controller.resume()
    startRecording()
    engine.calls.clear()

    controller.resume()                 // still RECORD
    controller.pause()
    engine.calls.clear()
    controller.pause()                  // already PAUSE

    assertTrue(engine.calls.isEmpty())
    assertEquals(RecordState.PAUSE, sink.states.last())
  }

  // --- interruption policy ---

  @Test
  fun `an interruption pause keeps the audio session`() {
    startRecording(testRecordConfig(audioInterruption = AudioInterruption.PAUSE_RESUME.ordinal))
    env.calls.clear()

    controller.onEnvironmentEvent(EnvironmentEvent.FocusLost)

    assertEquals(listOf("pause"), engine.calls.drop(1))
    assertTrue("focus request kept alive for auto-resume", env.calls.isEmpty())
    assertEquals(RecordState.PAUSE, sink.states.last())
  }

  @Test
  fun `focus loss then regain pauses then resumes`() {
    startRecording(testRecordConfig(audioInterruption = AudioInterruption.PAUSE_RESUME.ordinal))
    engine.calls.clear()

    controller.onEnvironmentEvent(EnvironmentEvent.FocusLost)
    controller.onEnvironmentEvent(EnvironmentEvent.FocusRegained)

    assertEquals(listOf("pause", "resume"), engine.calls)
    assertEquals(listOf(RecordState.RECORD, RecordState.PAUSE, RecordState.RECORD), sink.states)
  }

  @Test
  fun `a user pause on top of an interruption pause hands the session back`() {
    startRecording(testRecordConfig(audioInterruption = AudioInterruption.PAUSE_RESUME.ordinal))
    controller.onEnvironmentEvent(EnvironmentEvent.FocusLost)
    env.calls.clear()
    engine.calls.clear()

    controller.pause()

    // Focus is abandoned, so no regain can auto-resume what the user paused.
    assertEquals(listOf("release"), env.calls)
    assertTrue(engine.calls.isEmpty())
    assertEquals(RecordState.PAUSE, sink.states.last())
  }

  @Test
  fun `environment events before recording are ignored`() {
    controller.onEnvironmentEvent(EnvironmentEvent.FocusLost)
    assertTrue(engine.calls.isEmpty())
  }

  // --- stop / cancel / dispose ---

  @Test
  fun `stop releases the engine and the session, broadcasts STOP and returns the path`() {
    startRecording()
    env.calls.clear()

    val path = stop()

    assertEquals(config.path, path)
    assertEquals(listOf("stop"), engine.calls.drop(1))
    assertEquals(false, engine.deleteRequested)
    assertEquals(listOf("release"), env.calls)
    assertEquals(RecordState.STOP, sink.states.last())
    assertFalse(controller.isRecording)
  }

  @Test
  fun `stop answers only once the engine has finished tearing down`() {
    engine.deferStop = true
    startRecording()
    env.calls.clear()

    var path: String? = null
    var answered = false
    controller.stop { p -> path = p; answered = true }

    assertFalse("the engine has not finished yet", answered)
    assertTrue("the session is handed back on completion", env.calls.isEmpty())
    assertFalse("but the next take can already begin", controller.isRecording)

    engine.completeStop()

    assertTrue(answered)
    assertEquals(config.path, path)
    assertEquals(listOf("release"), env.calls)
    assertEquals(RecordState.STOP, sink.states.last())
  }

  @Test
  fun `a teardown error goes to the stream and stop still returns the path`() {
    engine.stopError = RuntimeException("muxer")
    startRecording()

    val path = stop()

    assertEquals(config.path, path)
    assertEquals(listOf("muxer"), sink.errors.map { it.message })
    assertEquals(RecordState.STOP, sink.states.last())
  }

  @Test
  fun `cancel asks the engine to delete and tears the environment down`() {
    startRecording()
    env.calls.clear()

    cancel()

    assertEquals(true, engine.deleteRequested)
    assertEquals(listOf("release", "dispose"), env.calls)
    assertFalse(controller.isRecording)
  }

  @Test
  fun `dispose tears the environment down even if the engine fails to stop`() {
    engine.stopThrows = IllegalStateException("wedged")
    startRecording()
    env.calls.clear()

    val thrown = runCatching { dispose() }.exceptionOrNull()

    assertTrue(thrown is IllegalStateException)
    assertEquals(listOf("dispose"), env.calls)
  }

  @Test
  fun `stop while idle does nothing`() {
    assertNull(stop())
    assertTrue(engine.calls.isEmpty())
    assertTrue(env.calls.isEmpty())
  }

  @Test
  fun `dispose stops the engine then tears the environment down`() {
    startRecording()
    env.calls.clear()

    dispose()

    assertEquals(listOf("stop"), engine.calls.drop(1))
    assertEquals(listOf("release", "dispose"), env.calls)
    assertFalse(controller.isRecording)
  }

  @Test
  fun `dispose while idle only tears the environment down`() {
    dispose()
    assertEquals(listOf("dispose"), env.calls)
    assertTrue(engine.calls.isEmpty())
  }

  // --- failure ---

  @Test
  fun `a spontaneous failure releases everything and surfaces the error`() {
    startRecording()
    env.calls.clear()

    controller.onCaptureFailure(engine, RuntimeException("boom"))

    assertEquals(listOf("stop"), engine.calls.drop(1))
    assertEquals(listOf("release"), env.calls)
    assertEquals(listOf("boom"), sink.errors.map { it.message })
    assertEquals(RecordState.STOP, sink.states.last())
    assertFalse(controller.isRecording)
  }

  // The PCM engine echoes the failure back as its stop error: that must not double the report.
  @Test
  fun `a failure echoed by the engine stop is reported once`() {
    startRecording()
    val cause = RuntimeException("boom")
    engine.stopError = cause

    controller.onCaptureFailure(engine, cause)

    assertEquals(listOf("boom"), sink.errors.map { it.message })
  }

  @Test
  fun `a teardown error on top of a failure is reported alongside it`() {
    startRecording()
    engine.stopError = RuntimeException("muxer")

    controller.onCaptureFailure(engine, RuntimeException("boom"))

    assertEquals(listOf("muxer", "boom"), sink.errors.map { it.message })
  }

  @Test
  fun `a failure from a superseded engine is ignored`() {
    startRecording()
    val dead = engine
    stop()
    sink.states.clear()
    env.calls.clear()

    controller.onCaptureFailure(dead, RuntimeException("late"))

    assertTrue(sink.errors.isEmpty())
    assertTrue(sink.states.isEmpty())
    assertTrue(env.calls.isEmpty())
  }

  // --- amplitude ---

  @Test
  fun `amplitude is the floor while idle or before the engine has started`() {
    val idle = controller.amplitude()
    assertEquals(DEFAULT_AMPLITUDE_DB, idle.current, 0.0)
    assertEquals(DEFAULT_AMPLITUDE_DB, idle.max, 0.0)

    env.deferPrepare = true
    controller.start(config) {}
    engine.amplitude = -20.0
    assertEquals(DEFAULT_AMPLITUDE_DB, controller.amplitude().current, 0.0)
  }

  @Test
  fun `amplitude reads the engine and tracks the peak`() {
    startRecording()

    engine.amplitude = -20.0
    val first = controller.amplitude()
    assertEquals(-20.0, first.current, 0.0)
    assertEquals(-20.0, first.max, 0.0)

    engine.amplitude = -30.0
    val second = controller.amplitude()
    assertEquals(-30.0, second.current, 0.0)
    assertEquals(-20.0, second.max, 0.0)
  }

  @Test
  fun `the peak resets between recordings`() {
    startRecording()
    engine.amplitude = -10.0
    controller.amplitude()
    stop()

    engine.amplitude = DEFAULT_AMPLITUDE_DB
    startRecording()
    assertEquals(DEFAULT_AMPLITUDE_DB, controller.amplitude().max, 0.0)
  }
}

private class DoneProbe {
  var calls = 0
  var error: Throwable? = null
  val done: (Throwable?) -> Unit = { e -> calls++; error = e }
}

private class FakeCaptureEngine : CaptureEngine {
  var config: RecordConfig? = null
  var effectiveConfig: RecordConfig? = null
  var startError: Exception? = null
  var stopError: Throwable? = null
  var stopThrows: Exception? = null
  var canPause = true
  var deleteRequested: Boolean? = null
  var deferStop = false
  override var amplitude: Double = DEFAULT_AMPLITUDE_DB

  val calls = mutableListOf<String>()
  private var pendingStop: ((Throwable?) -> Unit)? = null

  override fun start(): RecordConfig {
    calls += "start"
    startError?.let { throw it }
    return effectiveConfig ?: checkNotNull(config)
  }

  override fun pause(): Boolean {
    calls += "pause"
    return canPause
  }

  override fun resume(): Boolean {
    calls += "resume"
    return true
  }

  override fun stop(delete: Boolean, done: (Throwable?) -> Unit) {
    calls += "stop"
    deleteRequested = delete
    stopThrows?.let { throw it }
    if (deferStop) pendingStop = done else done(stopError)
  }

  fun completeStop() {
    pendingStop?.also { pendingStop = null; it(stopError) }
  }
}

private class FakeAudioEnvironment : AudioEnvironment {
  override var onEvent: (EnvironmentEvent) -> Unit = {}

  val calls = mutableListOf<String>()
  var deferPrepare = false
  var activateError: Exception? = null
  private var pendingReady: (() -> Unit)? = null

  override fun prepare(config: RecordConfig, onReady: () -> Unit) {
    calls += "prepare"
    if (deferPrepare) pendingReady = onReady else onReady()
  }

  fun completePrepare() {
    pendingReady?.also { pendingReady = null; it() }
  }

  override fun activate(config: RecordConfig) {
    calls += "activate"
    activateError?.let { throw it }
  }

  override fun release(config: RecordConfig) { calls += "release" }
  override fun dispose() { calls += "dispose" }
}

private class CapturingSink : RecorderSink {
  val states = mutableListOf<RecordState>()
  val errors = mutableListOf<Throwable>()
  val configChanges = mutableListOf<RecordConfig>()

  override fun onState(state: RecordState) { states += state }
  override fun onError(error: Throwable) { errors += error }
  override fun onConfigChanged(config: RecordConfig) { configChanges += config }
}
