package com.llfbandit.record.record.recorder.engine

import android.media.AudioDeviceInfo
import com.llfbandit.record.record.bluetooth.isBluetoothHeadset

/** Tracks the device a recording is on, and whether that device was unplugged. */
internal class RouteTracker {
  private var id: Int? = null
  private var bluetooth = false

  // Bluetooth moves capture off its device before the device is removed.
  private var left: Int? = null

  /** A loss was reported and capture has not started over since. */
  var isLost = false
    private set

  /** Starts over on [current], forgetting the device capture left and any loss. */
  fun reset(current: AudioDeviceInfo?) = reset(current?.id, current.isBluetooth())

  fun reset(current: Int?, bluetooth: Boolean) {
    id = current
    this.bluetooth = bluetooth
    left = null
    isLost = false
  }

  /** Follows capture to [current]; a move alone is never a loss. */
  fun moved(current: AudioDeviceInfo?) = moved(current?.id, current.isBluetooth())

  fun moved(current: Int?, bluetooth: Boolean) {
    // A stopped recorder reports no device: keep watching the last one.
    if (current == null || current == id) return
    // Any other device capture left still works, so its later unplug is no loss.
    left = id.takeIf { this.bluetooth }
    id = current
    this.bluetooth = bluetooth
  }

  /** @return true when [removed] holds the device in use, or the Bluetooth one capture just left. */
  fun lost(removed: Collection<Int>): Boolean {
    val hit = id?.let { it in removed } == true || left?.let { it in removed } == true
    if (hit) left = null
    return hit
  }

  /** @return true for the first report of a loss, false for the others until [reset]. */
  fun report(): Boolean {
    if (isLost) return false
    isLost = true
    return true
  }

  private fun AudioDeviceInfo?.isBluetooth() = this != null && isBluetoothHeadset(type)
}
