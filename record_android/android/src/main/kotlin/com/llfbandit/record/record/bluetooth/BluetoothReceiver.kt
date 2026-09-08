package com.llfbandit.record.record.bluetooth

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import com.llfbandit.record.record.util.DeviceUtils

interface BluetoothScoListener {
  fun onBlScoConnected()
  fun onBlScoDisconnected()
  fun onBlScoNone()
}

class BluetoothReceiver(
  private val context: Context,
  private val handler: Handler,
) : BroadcastReceiver() {
  private val filter = IntentFilter()
  private val audioManager: AudioManager =
    context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
  private var listener: BluetoothScoListener? = null
  private val devices = HashSet<AudioDeviceInfo>()
  private var audioDeviceCallback: AudioDeviceCallback? = null
  private var mRegistered: Boolean = false
  private var startNotified: Boolean = false

  init {
    filter.addAction(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
  }

  fun register(listener: BluetoothScoListener) {
    context.registerReceiver(this, filter, null, handler)
    mRegistered = true

    this.listener = listener

    audioDeviceCallback = object : AudioDeviceCallback() {
      override fun onAudioDevicesAdded(addedDevices: Array<AudioDeviceInfo>) {
        devices.addAll(DeviceUtils.filterSources(addedDevices.asList()))
      }

      override fun onAudioDevicesRemoved(removedDevices: Array<AudioDeviceInfo>) {
        devices.removeAll(DeviceUtils.filterSources(removedDevices.asList()).toSet())

        val hasBluetoothSco = devices.any {
          it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
        }
        if (!hasBluetoothSco && audioManager.isBluetoothScoAvailableOffCall) {
          stopBluetoothSco()
        }
      }
    }

    audioManager.registerAudioDeviceCallback(audioDeviceCallback, handler)

    // Handle devices that were already connected before the callback was registered.
    devices.addAll(
      DeviceUtils.filterSources(
        audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS).asList()
      )
    )
    maybeStartOrNotify(listener)
  }

  fun unregister() {
    stopBluetoothSco()

    if (audioDeviceCallback != null) {
      audioManager.unregisterAudioDeviceCallback(audioDeviceCallback)
      audioDeviceCallback = null
    }

    listener = null
    startNotified = false

    if (mRegistered) {
      context.unregisterReceiver(this)
      mRegistered = false
    }
  }

  private fun maybeStartOrNotify(listener: BluetoothScoListener) {
    val hasBluetoothSco = devices.any { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
    if (hasBluetoothSco && audioManager.isBluetoothScoAvailableOffCall) {
      startBluetoothSco(listener)
    } else {
      listener.onBlScoNone()
    }
  }

  override fun onReceive(context: Context, intent: Intent) {
    val state = intent.getIntExtra(AudioManager.EXTRA_SCO_AUDIO_STATE, -1)
    when (state) {
      AudioManager.SCO_AUDIO_STATE_CONNECTED -> {
        if (!startNotified) {
          startNotified = true
          listener?.onBlScoConnected()
        }
      }
      AudioManager.SCO_AUDIO_STATE_DISCONNECTED -> listener?.onBlScoDisconnected()
    }
  }

  private fun startBluetoothSco(listener: BluetoothScoListener? = this.listener) {
    if (!audioManager.isBluetoothScoAvailableOffCall) {
      return
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      for (device in audioManager.availableCommunicationDevices) {
        if (device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO) {
          audioManager.setCommunicationDevice(device)
          // setCommunicationDevice is synchronous; the legacy SCO broadcast is not
          // guaranteed to fire on API 31+, so notify the listener immediately.
          startNotified = true
          listener?.onBlScoConnected()
          return
        }
      }
      startNotified = true
      listener?.onBlScoNone()
    } else {
      @Suppress("DEPRECATION")
      if (!audioManager.isBluetoothScoOn()) {
        audioManager.startBluetoothSco()
        // async — onBlScoConnected will be called via ACTION_SCO_AUDIO_STATE_UPDATED broadcast
      }
    }
  }

  private fun stopBluetoothSco() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      audioManager.clearCommunicationDevice()
    } else {
      @Suppress("DEPRECATION")
      if (audioManager.isBluetoothScoOn()) {
        audioManager.stopBluetoothSco()
      }
    }
  }
}
