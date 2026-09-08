package com.llfbandit.record

import android.os.Handler
import android.os.HandlerThread

/** The one background thread that all recorder method calls and system callbacks run on. */
class RecorderDispatcher {
  private val thread = HandlerThread("com.llfbandit.record").apply { start() }

  // Handed to Android registration APIs so their callbacks land here directly.
  val handler = Handler(thread.looper)

  fun post(block: () -> Unit) {
    handler.post(block)
  }

  fun quit() {
    thread.quitSafely()
  }
}
