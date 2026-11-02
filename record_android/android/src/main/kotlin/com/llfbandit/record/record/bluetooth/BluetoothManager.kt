package com.llfbandit.record.record.bluetooth

import android.content.Context
import android.os.Handler
import com.llfbandit.record.record.model.RecordConfig

class BluetoothManager(private val context: Context, private val handler: Handler) {
  companion object {
    // Pre-31 SCO connects are answered by a broadcast that never comes if the link fails.
    private const val SCO_CONNECT_TIMEOUT_MS = 2_500L
  }

  private var receiver: BluetoothReceiver? = null
  // Answers a start still waiting for SCO when stopped.
  private var pendingDone: (() -> Unit)? = null

  fun maybeStart(config: RecordConfig, onDone: () -> Unit) {
    if (!config.manageBluetoothSco) {
      onDone()
      return
    }

    if (config.device != null && !isBluetoothHeadset(config.device.type)) {
      stop()
      onDone()
      return
    }

    if (receiver == null) {
      // onDone must run exactly once.
      var notified = false
      lateinit var onTimeout: Runnable
      fun notifyOnce() {
        if (notified) return
        notified = true
        pendingDone = null
        handler.removeCallbacks(onTimeout)
        onDone()
      }
      onTimeout = Runnable { notifyOnce() }
      pendingDone = ::notifyOnce

      // Armed first: register() may answer synchronously and cancel it right away.
      handler.postDelayed(onTimeout, SCO_CONNECT_TIMEOUT_MS)
      receiver = BluetoothReceiver(context, handler)
      receiver!!.register { notifyOnce() }
    } else {
      onDone()
    }
  }

  fun stop() {
    receiver?.unregister()
    receiver = null
    // A quitting handler drops the timeout, which would leave the start unanswered.
    pendingDone?.invoke()
  }
}
