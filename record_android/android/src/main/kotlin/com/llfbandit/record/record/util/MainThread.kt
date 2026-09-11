package com.llfbandit.record.record.util

import android.os.Handler
import android.os.Looper

/** The Flutter platform thread: every Result, EventSink and invokeMethod call must run here. */
object MainThread {
  private val handler = Handler(Looper.getMainLooper())

  fun post(block: () -> Unit) {
    handler.post(block)
  }
}
