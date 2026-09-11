package com.llfbandit.record.record.recorder.engine

import com.llfbandit.record.testRecordConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

class PcmCaptureEngineTest {
  private val events = mutableListOf<CaptureEvent>()

  private fun engine(path: String? = "/tmp/record-test.wav") =
    PcmCaptureEngine(testRecordConfig(path = path)) { _, event -> events += event }

  private fun stop(engine: PcmCaptureEngine, delete: Boolean = false): Throwable? {
    var error: Throwable? = null
    var answered = false
    engine.stop(delete) { e -> error = e; answered = true }
    assertTrue("stop must answer", answered)
    return error
  }

  @Test
  fun `amplitude is the default before start`() {
    assertEquals(DEFAULT_AMPLITUDE_DB, engine().amplitude, 0.0)
  }

  @Test
  fun `pause and resume before start are refused`() {
    val engine = engine()
    assertFalse(engine.pause())
    assertFalse(engine.resume())
    assertTrue(events.isEmpty())
  }

  @Test
  fun `stop before start is a clean no-op`() {
    assertNull(stop(engine()))
    assertTrue(events.isEmpty())
  }

  @Test
  fun `cancel before start deletes the output file`() {
    val file = File.createTempFile("record-engine", ".wav").apply { writeText("stale") }

    assertNull(stop(engine(file.absolutePath), delete = true))

    assertFalse("output file must be removed", file.exists())
  }

  @Test
  fun `a startup failure throws and leaves the engine stoppable`() {
    val engine = engine(path = null)   // wav + stream -> checkStreamSupport throws
    try {
      engine.start()
      fail("start should fail for a non-streamable encoder")
    } catch (_: IllegalArgumentException) {
      // expected
    }

    assertNull(stop(engine))
    assertFalse(engine.pause())
    assertTrue("a failed start reports through the exception only", events.isEmpty())
  }
}
