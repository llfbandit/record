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
      val listener = object : BluetoothScoListener {
        // onDone answers a Flutter call, which must happen exactly once.
        private var notified = false

        val onTimeout = Runnable { notifyOnce() }

        fun notifyOnce() {
          if (notified) return
          notified = true
          handler.removeCallbacks(onTimeout)
          onDone()
        }

        override fun onBlScoConnected() = notifyOnce()
        override fun onBlScoNone() = notifyOnce()
        override fun onBlScoDisconnected() {}
      }

      // Armed first: register() may answer synchronously and cancel it right away.
      handler.postDelayed(listener.onTimeout, SCO_CONNECT_TIMEOUT_MS)
      receiver = BluetoothReceiver(context, handler)
      receiver!!.register(listener)
    } else {
      onDone()
    }
  }

  fun stop() {
    receiver?.unregister()
    receiver = null
  }
}
