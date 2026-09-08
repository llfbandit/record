package com.llfbandit.record.record.bluetooth

import android.content.Context
import android.media.AudioDeviceInfo
import android.os.Handler
import com.llfbandit.record.record.model.RecordConfig

class BluetoothManager(private val context: Context, private val handler: Handler) {
  private var receiver: BluetoothReceiver? = null

  fun maybeStart(config: RecordConfig, onDone: () -> Unit) {
    if (!config.manageBluetoothSco) {
      onDone()
      return
    }

    if (config.device != null && config.device.type != AudioDeviceInfo.TYPE_BLUETOOTH_SCO) {
      stop()
      onDone()
      return
    }

    if (receiver == null) {
      receiver = BluetoothReceiver(context, handler)
      receiver!!.register(object : BluetoothScoListener {
        override fun onBlScoConnected() { onDone() }
        override fun onBlScoNone() { onDone() }
        override fun onBlScoDisconnected() {}
      })
    } else {
      onDone()
    }
  }

  fun stop() {
    receiver?.unregister()
    receiver = null
  }
}
