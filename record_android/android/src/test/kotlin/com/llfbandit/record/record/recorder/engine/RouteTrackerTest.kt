package com.llfbandit.record.record.recorder.engine

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Checks when RouteTracker counts an unplug as a loss. */
class RouteTrackerTest {
  private val tracker = RouteTracker()

  @Test
  fun `unplugging the device in use is a loss`() {
    tracker.reset(7, bluetooth = false)
    assertTrue(tracker.lost(listOf(7)))
  }

  @Test
  fun `unplugging another device is not a loss`() {
    tracker.reset(7, bluetooth = false)
    assertFalse(tracker.lost(listOf(9)))
  }

  @Test
  fun `a move alone is not a loss`() {
    // Plugging in a headset moves capture to it; the old device is still there.
    tracker.reset(7, bluetooth = false)
    tracker.moved(9, bluetooth = false)
    assertFalse(tracker.lost(emptyList()))
  }

  @Test
  fun `unplugging the Bluetooth device capture just left is a loss`() {
    // Bluetooth moves capture off its device before the device is removed.
    tracker.reset(7, bluetooth = true)
    tracker.moved(9, bluetooth = false)
    assertTrue(tracker.lost(listOf(7)))
  }

  @Test
  fun `unplugging another device capture left is not a loss`() {
    // Plugging in a wired headset moves capture off a USB mic, which stays usable.
    tracker.reset(7, bluetooth = false)
    tracker.moved(9, bluetooth = false)
    assertFalse(tracker.lost(listOf(7)))
  }

  @Test
  fun `unplugging the device capture moved to is a loss`() {
    tracker.reset(7, bluetooth = false)
    tracker.moved(9, bluetooth = false)
    assertTrue(tracker.lost(listOf(9)))
  }

  @Test
  fun `the device left before the last move is forgotten`() {
    tracker.reset(7, bluetooth = true)
    tracker.moved(9, bluetooth = true)
    tracker.moved(11, bluetooth = false)
    assertFalse(tracker.lost(listOf(7)))
  }

  @Test
  fun `no device keeps watching the last one`() {
    // A stopped recorder reports no device.
    tracker.reset(7, bluetooth = false)
    tracker.moved(null, bluetooth = false)
    assertTrue(tracker.lost(listOf(7)))
  }

  @Test
  fun `the device just left is reported once`() {
    tracker.reset(7, bluetooth = true)
    tracker.moved(9, bluetooth = false)
    assertTrue(tracker.lost(listOf(7)))
    assertFalse(tracker.lost(listOf(7)))
  }

  @Test
  fun `nothing is lost before a device is known`() {
    tracker.reset(null, bluetooth = false)
    assertFalse(tracker.lost(listOf(7)))
  }

  @Test
  fun `a loss is reported once until capture starts over`() {
    assertTrue(tracker.report())
    assertFalse(tracker.report())
    assertTrue(tracker.isLost)

    tracker.reset(9, bluetooth = false)

    assertFalse(tracker.isLost)
    assertTrue(tracker.report())
  }
}
