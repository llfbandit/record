package com.llfbandit.record.record.recorder.engine

/** Tracks the device a recording is on, and whether that device was unplugged. */
internal class RouteTracker {
  // The routing and device callbacks may run on other threads than the engine.
  @Volatile
  private var id: Int? = null

  // Bluetooth moves capture off its device before the device is removed.
  @Volatile
  private var left: Int? = null

  /** Starts over on [current] and forgets the device capture left. */
  fun reset(current: Int?) {
    id = current
    left = null
  }

  /** Follows capture to [current]; a move alone is never a loss. */
  fun moved(current: Int?) {
    // A stopped recorder reports no device: keep watching the last one.
    if (current == null || current == id) return
    left = id
    id = current
  }

  /** @return true when [removed] holds the device in use, or the one capture just left. */
  fun lost(removed: Collection<Int>): Boolean {
    val hit = id?.let { it in removed } == true || left?.let { it in removed } == true
    if (hit) left = null
    return hit
  }
}
