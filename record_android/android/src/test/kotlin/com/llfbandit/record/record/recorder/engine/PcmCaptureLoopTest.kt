package com.llfbandit.record.record.recorder.engine

import com.llfbandit.record.record.recorder.AudioDeadObjectException
import com.llfbandit.record.record.recorder.PcmSource
import android.media.AudioDeviceInfo
import com.llfbandit.record.testAudioDevice
import com.llfbandit.record.testRecordConfig
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/** Drives the running capture loop into route losses and silent stops. */
@RunWith(RobolectricTestRunner::class)
class PcmCaptureLoopTest {
  private lateinit var file: File
  private lateinit var source: FakeSource
  private lateinit var engine: PcmCaptureEngine
  private val events = LinkedBlockingQueue<CaptureEvent>()
  private val mic = testAudioDevice(id = 7)
  // Set while the engine watches for unplugs, so tests can fire one.
  @Volatile private var onRemoved: ((List<Int>) -> Unit)? = null

  @Before
  fun setUp() {
    file = File.createTempFile("record-loop", ".wav")
    source = FakeSource()
    engine = PcmCaptureEngine(
      testRecordConfig(path = file.absolutePath),
      { _, event -> events.put(event) },
      { callback -> onRemoved = callback; AutoCloseable { onRemoved = null } },
      { _, _ -> source },
    )
    engine.start()
    // The loop reads its first device at start-up, so let it settle before changing anything.
    assertTrue("the loop must be capturing", awaitReads())
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

    assertTrue("the loop must report the loss", awaitRouteLost())

    val readsWhileHalted = source.readCount
    Thread.sleep(100)
    assertEquals("a halted loop must not spin on a dead source", readsWhileHalted, source.readCount)
    assertNull("the loss is reported once", events.poll(100, TimeUnit.MILLISECONDS))
  }

  @Test
  fun `unplugging the device in use reports a route loss`() {
    unplug(1)

    assertTrue(awaitRouteLost())
  }

  @Test
  fun `unplugging the device capture just left reports a route loss`() {
    // Bluetooth moves capture off its device before the device is removed.
    moveTo(9)
    unplug(1)

    assertTrue(awaitRouteLost())
  }

  @Test
  fun `moving to a newly plugged device is not a route loss`() {
    moveTo(9)

    assertNull(events.poll(200, TimeUnit.MILLISECONDS))
  }

  @Test
  fun `unplugging another device is not a route loss`() {
    unplug(9)

    assertNull(events.poll(200, TimeUnit.MILLISECONDS))
  }

  @Test
  fun `a route change while paused is not a route loss`() {
    pauseSource()
    source.fireRouteChanged()

    assertNull(events.poll(200, TimeUnit.MILLISECONDS))
  }

  @Test
  fun `unplugging the device while paused reports a route loss`() {
    pauseSource()
    source.fireRouteChanged()
    unplug(1)

    assertTrue(awaitRouteLost())
  }

  @Test
  fun `stop stops watching for unplugged devices`() {
    stop()

    assertNull(onRemoved)
  }

  // --- reroute ---

  @Test
  fun `a reroute after a dead read rebuilds the source and resumes reading`() {
    source.failNextRead(AudioDeadObjectException())
    assertTrue(awaitRouteLost())

    assertTrue(reroute(null))

    assertEquals(1, source.recreateCount)
    assertNull("a follow must not pin a device", source.lastRecreateDevice)
    assertTrue("capture must resume by itself", awaitReads())
  }

  @Test
  fun `a reroute that cannot rebuild answers false and stays halted`() {
    source.recreateError = IllegalStateException("mic busy")
    source.failNextRead(AudioDeadObjectException())
    assertTrue(awaitRouteLost())

    assertFalse(reroute(mic))

    assertEquals("every attempt is used", 3, source.recreateCount)
  }

  @Test
  fun `a reroute of a live source re-aims it instead of rebuilding`() {
    unplug(1)
    assertTrue(awaitRouteLost())

    assertTrue(reroute(mic))

    assertEquals("a live source is never rebuilt", 0, source.recreateCount)
    assertEquals(mic, source.lastPreferredDevice)
  }

  @Test
  fun `a live source that fails to restart stops reading until a rebuild`() {
    unplug(1)
    assertTrue(awaitRouteLost())
    source.startOk = false

    assertFalse(reroute(null))

    val readsWhileHalted = source.readCount
    Thread.sleep(100)
    assertEquals("a stopped source must not be read", readsWhileHalted, source.readCount)
    assertNull("nothing fails while waiting", events.poll(100, TimeUnit.MILLISECONDS))

    source.startOk = true
    assertTrue(reroute(null))
    assertEquals("the next reroute rebuilds it", 1, source.recreateCount)
  }

  @Test
  fun `a second route loss is reported once the first has been answered`() {
    source.failNextRead(AudioDeadObjectException())
    assertTrue(awaitRouteLost())
    assertTrue(reroute(null))

    source.failNextRead(AudioDeadObjectException())

    assertTrue("answering re-arms the report", awaitRouteLost())
  }

  // --- pause / resume ---

  @Test
  fun `pause stops the source so nothing is captured while paused`() {
    engine.pause()

    assertTrue(await { source.stopCount == 1 })
    val readsWhilePaused = source.readCount
    Thread.sleep(100)
    assertEquals(readsWhilePaused, source.readCount)
  }

  @Test
  fun `resume starts the source again`() {
    engine.pause()
    assertTrue(await { source.stopCount == 1 })

    engine.resume()

    assertTrue(awaitReads())
  }

  @Test
  fun `a resume the source refuses reports a route loss instead of failing`() {
    engine.pause()
    assertTrue(await { source.stopCount == 1 })
    source.startOk = false

    engine.resume()

    assertTrue("the device vanished while stopped", awaitRouteLost())
    assertNull("the session must survive it", events.poll(100, TimeUnit.MILLISECONDS))
  }

  @Test
  fun `a resume after a route loss rebuilds pinned to the given device`() {
    source.failNextRead(AudioDeadObjectException())
    assertTrue(awaitRouteLost())
    engine.pause()

    assertTrue(reroute(mic))

    assertEquals(1, source.recreateCount)
    assertEquals(mic, source.lastRecreateDevice)
    assertEquals("a paused rebuild stays stopped", 0, source.startCountSince(1))
  }

  // --- teardown ---

  @Test
  fun `a stop while halted on a route loss still answers`() {
    source.failNextRead(AudioDeadObjectException())
    assertTrue(awaitRouteLost())

    assertNull("stop must not hang", stop())
    assertEquals(1, source.releaseCount)
  }

  @Test
  fun `a read failure that is not a route loss ends the recording`() {
    source.failNextRead(IllegalStateException("broken"))

    val event = events.poll(2, TimeUnit.SECONDS)
    assertTrue("a plain failure is not a route change", event is CaptureEvent.Failed)
    assertEquals("broken", (event as CaptureEvent.Failed).cause.message)
  }

  // The controller hears of the failure later: meanwhile nothing may look like it worked.
  @Test
  fun `a failed loop refuses pause, resume and reroute`() {
    source.failNextRead(IllegalStateException("broken"))
    assertTrue(events.poll(2, TimeUnit.SECONDS) is CaptureEvent.Failed)

    assertFalse(engine.pause())
    assertFalse(engine.resume())
    val rerouted = LinkedBlockingQueue<Boolean>()
    engine.reroute(null) { rerouted.put(it) }
    assertEquals(false, rerouted.poll(2, TimeUnit.SECONDS))
  }

  // --- helpers ---

  private fun moveTo(deviceId: Int) {
    source.routedDeviceId = deviceId
    source.fireRouteChanged()
  }

  private fun unplug(vararg deviceIds: Int) = checkNotNull(onRemoved)(deviceIds.toList())

  // A stopped AudioRecord reports no device.
  private fun pauseSource() {
    engine.pause()
    assertTrue(await { source.stopCount == 1 })
    source.routedDeviceId = null
  }

  private fun awaitRouteLost(): Boolean =
    events.poll(2, TimeUnit.SECONDS) === CaptureEvent.RouteLost

  private fun awaitReads(): Boolean {
    val before = source.readCount
    return await { source.readCount > before }
  }

  private fun await(condition: () -> Boolean): Boolean {
    val deadline = System.currentTimeMillis() + 2000
    while (System.currentTimeMillis() < deadline) {
      if (condition()) return true
      Thread.sleep(5)
    }
    return false
  }

  private fun reroute(device: AudioDeviceInfo?): Boolean {
    val answered = CountDownLatch(1)
    var ok = false
    engine.reroute(device) { result -> ok = result; answered.countDown() }
    assertTrue("reroute must answer", answered.await(2, TimeUnit.SECONDS))
    return ok
  }

  private fun stop(): Throwable? {
    val answered = CountDownLatch(1)
    var error: Throwable? = null
    engine.stop(delete = false) { e -> error = e; answered.countDown() }
    assertTrue("stop must answer", answered.await(2, TimeUnit.SECONDS))
    return error
  }
}

/** Stands in for the AudioRecord the loop would otherwise need a device to drive. */
private class FakeSource : PcmSource {
  @Volatile var startOk = true
  // Capture starts on device 1.
  @Volatile override var routedDeviceId: Int? = 1
  @Volatile var recreateError: Exception? = null

  @Volatile var readCount = 0
  @Volatile var stopCount = 0
  @Volatile var releaseCount = 0
  @Volatile var recreateCount = 0
  @Volatile var lastRecreateDevice: AudioDeviceInfo? = null
  @Volatile var lastPreferredDevice: AudioDeviceInfo? = null

  private val failures = LinkedBlockingQueue<Throwable>()
  private var startCount = 0
  private var onRouteChanged: (() -> Unit)? = null

  fun failNextRead(cause: Throwable) = failures.put(cause)

  fun fireRouteChanged() = onRouteChanged?.invoke()

  fun startCountSince(mark: Int) = startCount - mark

  override fun start(): Boolean {
    if (startOk) startCount++
    return startOk
  }

  override fun stop() {
    stopCount++
  }

  override fun release() {
    releaseCount++
  }

  override fun read(): ByteArray {
    failures.poll()?.let { throw it }
    readCount++
    // Sleep briefly so the loop neither spins hot nor starves its inbox.
    Thread.sleep(5)
    return ByteArray(2)
  }

  override fun getAmplitude() = DEFAULT_AMPLITUDE_DB

  override fun watchRoute(onChanged: () -> Unit) {
    onRouteChanged = onChanged
  }

  override fun preferDevice(device: AudioDeviceInfo?) {
    lastPreferredDevice = device
  }

  override fun recreate(device: AudioDeviceInfo?) {
    recreateCount++
    lastRecreateDevice = device
    recreateError?.let { throw it }
  }
}
