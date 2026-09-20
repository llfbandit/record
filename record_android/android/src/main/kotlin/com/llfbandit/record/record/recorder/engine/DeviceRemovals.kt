package com.llfbandit.record.record.recorder.engine

/** Reports input devices as they are unplugged. */
fun interface DeviceRemovals {
  /** @return a handle that stops the reports. */
  fun watch(onRemoved: (deviceIds: List<Int>) -> Unit): AutoCloseable
}
