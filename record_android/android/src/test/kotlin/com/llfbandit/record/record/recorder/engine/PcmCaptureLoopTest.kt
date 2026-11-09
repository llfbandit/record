package com.llfbandit.record.record.recorder.engine

import android.media.AudioDeviceInfo
import android.os.Handler
import android.os.Looper
import com.llfbandit.record.record.recorder.AudioDeadObjectException
import com.llfbandit.record.record.recorder.PcmSource
import com.llfbandit.record.testAudioDevice
import com.llfbandit.record.testRecordConfig
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.io.File
import java.time.Duration

/** Drives scheduled capture into route losses and silent stops; each [tick] is one read. */
@RunWith(RobolectricTestRunner::class)
class PcmCaptureLoopTest {
  private lateinit var file: File
  private lateinit var source: FakeSource
  private lateinit var engine: PcmCaptureEngine
  private val events = mutableListOf<CaptureEvent>()
  private val mic = testAudioDevice(id = 7)
  // Set while the engine watches for unplugs, so tests can fire one.
  private var onRemoved: ((List<Int>) -> Unit)? = null
  private var hasInput = true

  @Before
  fun setUp() {
    file = File.createTempFile("record-loop", ".wav")
    source = FakeSource()
    engine = PcmCaptureEngine(
      testRecordConfig(path = file.absolutePath),
      { _, event -> events += event },
      { callback -> onRemoved = callback; AutoCloseable { onRemoved = null } },
      Handler(Looper.getMainLooper()),
      { hasInput },
      { _, _ -> source },
    )
    engine.start()
    assertTrue("capture must be running", readsOnTick())
  }

  @After
  fun tearDown() {
    stop()
    file.delete()
  }

  // --- route loss ---

  @Test
  fun `a dead read reports one route loss and stops reading`() {
    source.failNextRead(AudioDeadObjectException())
    tick()

    assertRouteLost()
    assertFalse("a halted capture must not read a dead source", readsOnTick())
    assertTrue("the loss is reported once", events.isEmpty())
  }

  @Test
  fun `unplugging the device in use reports a route loss`() {
    unplug(1)

    assertRouteLost()
  }

  @Test
  fun `unplugging the Bluetooth device capture just left reports a route loss`() {
    moveTo(5, AudioDeviceInfo.TYPE_BLUETOOTH_SCO)
    // Bluetooth moves capture off its device before the device is removed.
    moveTo(9)
    unplug(5)

    assertRouteLost()
  }

  @Test
  fun `unplugging another device capture left is not a route loss`() {
    moveTo(9)
    unplug(1)

    assertTrue(events.isEmpty())
  }

  @Test
  fun `moving to a newly plugged device is not a route loss`() {
    moveTo(9)

    assertTrue(events.isEmpty())
  }

  @Test
  fun `unplugging another device is not a route loss`() {
    unplug(9)

    assertTrue(events.isEmpty())
  }

  @Test
  fun `a route change while paused is not a route loss`() {
    pauseSource()
    source.fireRouteChanged()

    assertTrue(events.isEmpty())
  }

  @Test
  fun `unplugging the device while paused reports a route loss`() {
    pauseSource()
    source.fireRouteChanged()
    unplug(1)

    assertRouteLost()
  }

  @Test
  fun `stop stops watching for unplugged devices`() {
    stop()

    assertNull(onRemoved)
  }

  // --- captureOn ---

  @Test
  fun `a capture after a dead read rebuilds the source and resumes reading`() {
    source.failNextRead(AudioDeadObjectException())
    tick()
    assertRouteLost()

    assertTrue(captureOn(null) is Bound.On)

    assertEquals(1, source.recreateCount)
    assertNull("a follow must not pin a device", source.lastRecreateDevice)
    assertTrue("capture must resume by itself", readsOnTick())
  }

  @Test
  fun `a capture that cannot rebuild answers NoInput and stays halted`() {
    hasInput = false
    source.recreateError = IllegalStateException("mic busy")
    source.failNextRead(AudioDeadObjectException())
    tick()
    assertRouteLost()

    assertEquals(Bound.NoInput, captureOn(mic))

    assertFalse(readsOnTick())
  }

  @Test
  fun `a rebuild that fails with a device present ends the recording`() {
    source.recreateError = SecurityException("permission revoked")
    source.failNextRead(AudioDeadObjectException())
    tick()
    assertRouteLost()

    val bound = captureOn(mic)

    assertEquals("permission revoked", (bound as Bound.Failed).cause.message)
    assertNull("the answer already carried it", stop())
  }

  @Test
  fun `a capture on a live source re-aims it instead of rebuilding`() {
    unplug(1)
    assertRouteLost()

    assertTrue(captureOn(mic) is Bound.On)

    assertEquals("a live source is never rebuilt", 0, source.recreateCount)
    assertEquals(mic, source.lastPreferredDevice)
  }

  @Test
  fun `a capture after a paused unplug rebuilds the source`() {
    unplug(1)
    assertRouteLost()
    engine.pause()

    assertTrue(captureOn(mic) is Bound.On)

    assertEquals("a stopped source may be dead though it starts", 1, source.recreateCount)
    assertEquals(mic, source.lastRecreateDevice)
    assertTrue(readsOnTick())
  }

  @Test
  fun `a capture that throws answers Failed and ends the recording`() {
    unplug(1)
    assertRouteLost()
    source.preferError = IllegalStateException("broken")

    val bound = captureOn(mic)

    assertEquals("broken", (bound as Bound.Failed).cause.message)
    assertTrue("the answer carries it, not an event", events.isEmpty())
    assertNull(stop())
  }

  @Test
  fun `a live source that fails to restart stops reading until a rebuild`() {
    unplug(1)
    assertRouteLost()
    source.startOk = false

    assertEquals(Bound.NoInput, captureOn(null))

    assertFalse("a stopped source must not be read", readsOnTick())
    assertTrue("nothing fails while waiting", events.isEmpty())

    source.startOk = true
    assertTrue(captureOn(null) is Bound.On)
    assertEquals("the next capture rebuilds it", 1, source.recreateCount)
  }

  @Test
  fun `a second route loss is reported once the first has been answered`() {
    source.failNextRead(AudioDeadObjectException())
    tick()
    assertRouteLost()
    assertTrue(captureOn(null) is Bound.On)

    source.failNextRead(AudioDeadObjectException())
    tick()

    assertRouteLost()
  }

  // --- pause / resume ---

  @Test
  fun `pause stops the source so nothing is captured while paused`() {
    assertTrue(engine.pause())

    assertEquals(1, source.stopCount)
    assertFalse(readsOnTick())
  }

  @Test
  fun `pause encodes what was captured since the last read`() {
    val before = source.readCount

    engine.pause()

    assertEquals(before + 1, source.readCount)
  }

  @Test
  fun `a dead read on pause waits for a rebuild`() {
    source.failNextRead(AudioDeadObjectException())

    assertTrue(engine.pause())
    assertEquals("a dead source is not stopped", 0, source.stopCount)
    assertTrue(events.isEmpty())

    assertTrue(engine.resume(null) is Bound.On)
    assertEquals(1, source.recreateCount)
  }

  @Test
  fun `a read failure on pause ends the recording`() {
    source.failNextRead(IllegalStateException("broken"))

    val error = assertThrows(IllegalStateException::class.java) { engine.pause() }

    assertEquals("broken", error.message)
    assertTrue("the throw carries it, not an event", events.isEmpty())
    assertNull(stop())
  }

  @Test
  fun `amplitude is the floor while nothing is captured`() {
    source.level = -3.0
    assertEquals(-3.0, engine.amplitude, 0.0)

    engine.pause()

    assertEquals(DEFAULT_AMPLITUDE_DB, engine.amplitude, 0.0)
  }

  @Test
  fun `resume starts the source again`() {
    engine.pause()

    assertSame(Bound.Resumed, engine.resume(mic))

    assertEquals("a plain resume moves nothing", 0, source.recreateCount)
    assertTrue(readsOnTick())
  }

  @Test
  fun `a resume the source refuses waits for a rebuild instead of failing`() {
    engine.pause()
    source.startOk = false

    assertEquals(Bound.NoInput, engine.resume(null))
    assertTrue("the session must survive it", events.isEmpty())

    source.startOk = true
    assertTrue(engine.resume(null) is Bound.On)
    assertEquals("each resume rebuilds a source that refused to start", 2, source.recreateCount)
  }

  @Test
  fun `a resume after a paused unplug moves capture to the given device`() {
    engine.pause()
    unplug(1)
    assertRouteLost()
    source.routedDevice = mic

    val bound = engine.resume(mic)

    assertEquals(mic, (bound as Bound.On).device)
    assertEquals(mic, source.lastRecreateDevice)
    assertTrue(readsOnTick())
  }

  @Test
  fun `a capture after a paused route loss rebuilds pinned to the given device and runs`() {
    source.failNextRead(AudioDeadObjectException())
    tick()
    assertRouteLost()
    engine.pause()
    source.routedDevice = mic

    val bound = captureOn(mic)

    assertEquals(mic, (bound as Bound.On).device)
    assertEquals(1, source.recreateCount)
    assertEquals(mic, source.lastRecreateDevice)
    assertTrue("capture runs again", readsOnTick())
  }

  @Test
  fun `a capture that Android routes elsewhere reports no device`() {
    unplug(1)
    assertRouteLost()
    source.routedDevice = testAudioDevice(id = 9)

    val bound = captureOn(mic)

    assertNull((bound as Bound.On).device)
  }

  // --- teardown ---

  @Test
  fun `stop encodes the rest and the unfinished chunk`() {
    val before = source.readCount

    assertNull(stop())

    assertEquals(before + 1, source.readCount)
    assertEquals(1, source.flushCount)
  }

  @Test
  fun `a stop that finds the device gone is no failure`() {
    source.failNextRead(AudioDeadObjectException())

    assertNull(stop())
  }

  @Test
  fun `a stop while halted on a route loss still answers`() {
    source.failNextRead(AudioDeadObjectException())
    tick()
    assertRouteLost()

    assertNull(stop())
    assertEquals(1, source.releaseCount)
  }

  @Test
  fun `a read failure that is not a route loss ends the recording`() {
    source.failNextRead(IllegalStateException("broken"))
    tick()

    val event = events.removeFirstOrNull()
    assertTrue("a plain failure is not a route change", event is CaptureEvent.Failed)
    assertEquals("broken", (event as CaptureEvent.Failed).cause.message)
    assertNull("the event already carried it", stop())
  }

  // The controller hears of the failure later: meanwhile nothing may look like it worked.
  @Test
  fun `a failed capture refuses pause, resume and captureOn`() {
    source.failNextRead(IllegalStateException("broken"))
    tick()
    assertTrue(events.removeFirstOrNull() is CaptureEvent.Failed)

    assertFalse(engine.pause())
    assertThrows(IllegalStateException::class.java) { engine.resume(null) }
    assertEquals(Bound.NoInput, captureOn(null))
  }

  // --- helpers ---

  private fun tick() = shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(PcmCaptureEngine.READ_PERIOD_MS))

  private fun readsOnTick(): Boolean {
    val before = source.readCount
    tick()
    return source.readCount > before
  }

  private fun moveTo(deviceId: Int, type: Int = AudioDeviceInfo.TYPE_USB_DEVICE) {
    source.routedDevice = testAudioDevice(deviceId, type)
    source.fireRouteChanged()
  }

  private fun unplug(vararg deviceIds: Int) = checkNotNull(onRemoved)(deviceIds.toList())

  // A stopped AudioRecord reports no device.
  private fun pauseSource() {
    engine.pause()
    source.routedDevice = null
  }

  private fun assertRouteLost() = assertSame(CaptureEvent.RouteLost, events.removeFirstOrNull())

  private fun captureOn(device: AudioDeviceInfo?): Bound = engine.captureOn(device)

  private fun stop(): Throwable? = engine.stop(delete = false)
}

/** Stands in for the AudioRecord the engine would otherwise need a device to drive. */
private class FakeSource : PcmSource {
  var startOk = true
  // Capture starts on device 1.
  override var routedDevice: AudioDeviceInfo? = testAudioDevice(id = 1)
  var recreateError: Exception? = null
  var preferError: Exception? = null

  var readCount = 0
  var stopCount = 0
  var releaseCount = 0
  var recreateCount = 0
  var flushCount = 0
  var lastRecreateDevice: AudioDeviceInfo? = null
  var lastPreferredDevice: AudioDeviceInfo? = null

  private val failures = ArrayDeque<Throwable>()
  private var onRouteChanged: (() -> Unit)? = null
  // One chunk per tick: the read after a chunk finds nothing new.
  private var chunkReady = true

  fun failNextRead(cause: Throwable) = failures.addLast(cause)

  fun fireRouteChanged() = onRouteChanged?.invoke()

  override fun start(): Boolean {
    return startOk
  }

  override fun stop() {
    stopCount++
  }

  override fun release() {
    releaseCount++
  }

  override fun read(): ByteArray {
    failures.removeFirstOrNull()?.let { throw it }
    if (!chunkReady) {
      chunkReady = true
      return ByteArray(0)
    }
    chunkReady = false
    readCount++
    return ByteArray(2)
  }

  override fun flush(): ByteArray {
    flushCount++
    return ByteArray(2)
  }

  var level = DEFAULT_AMPLITUDE_DB
  override fun getAmplitude() = level

  override fun watchRoute(handler: Handler, onChanged: () -> Unit) {
    onRouteChanged = onChanged
  }

  override fun preferDevice(device: AudioDeviceInfo?) {
    preferError?.let { throw it }
    lastPreferredDevice = device
  }

  override fun recreate(device: AudioDeviceInfo?) {
    recreateCount++
    lastRecreateDevice = device
    recreateError?.let { throw it }
  }
}
