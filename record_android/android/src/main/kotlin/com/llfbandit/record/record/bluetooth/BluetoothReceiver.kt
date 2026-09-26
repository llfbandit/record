package com.llfbandit.record.record.bluetooth

import android.annotation.TargetApi
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

/** Both carry a headset mic; LE Audio only exists from API 31. */
internal fun isBluetoothHeadset(type: Int): Boolean =
  type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
    (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && type == AudioDeviceInfo.TYPE_BLE_HEADSET)

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
  private var communicationDeviceListener: AudioManager.OnCommunicationDeviceChangedListener? = null

  init {
    filter.addAction(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
  }

  fun register(listener: BluetoothScoListener) {
    context.registerReceiver(this, filter, null, handler)
    mRegistered = true

    this.listener = listener

    audioDeviceCallback = object : AudioDeviceCallback() {
      override fun onAudioDevicesAdded(addedDevices: Array<AudioDeviceInfo>) {
        val hadBluetoothSco = devices.any { isBluetoothHeadset(it.type) }
        devices.addAll(DeviceUtils.filterSources(addedDevices.asList()))

        // The removal stopped SCO, and nothing else starts it again for the next take or a resume.
        val hasBluetoothSco = devices.any { isBluetoothHeadset(it.type) }
        if (startNotified && !hadBluetoothSco && hasBluetoothSco) {
          startBluetoothSco()
        }
      }

      override fun onAudioDevicesRemoved(removedDevices: Array<AudioDeviceInfo>) {
        devices.removeAll(DeviceUtils.filterSources(removedDevices.asList()).toSet())

        val hasBluetoothSco = devices.any { isBluetoothHeadset(it.type) }
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
    stopWaitingForCommunicationDevice()
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
    val hasBluetoothSco = devices.any { isBluetoothHeadset(it.type) }
    if (hasBluetoothSco && audioManager.isBluetoothScoAvailableOffCall) {
      startBluetoothSco(listener)
    } else {
      // Stays registered, so another app's later SCO link must not look like ours starting.
      notifyNone(listener)
    }
  }

  override fun onReceive(context: Context, intent: Intent) {
    val state = intent.getIntExtra(AudioManager.EXTRA_SCO_AUDIO_STATE, Int.MIN_VALUE)
    when (state) {
      AudioManager.SCO_AUDIO_STATE_CONNECTED -> {
        if (!startNotified) {
          startNotified = true
          listener?.onBlScoConnected()
        }
      }
      // The link failed: answer now instead of waiting for a connect that never comes.
      AudioManager.SCO_AUDIO_STATE_ERROR -> if (!startNotified) notifyNone(listener)
      AudioManager.SCO_AUDIO_STATE_DISCONNECTED -> listener?.onBlScoDisconnected()
    }
  }

  // Every path must notify: prepare() waits on this.
  private fun startBluetoothSco(listener: BluetoothScoListener? = this.listener) {
    if (!audioManager.isBluetoothScoAvailableOffCall) {
      notifyNone(listener)
      return
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      val available = audioManager.availableCommunicationDevices
      // LE Audio wins over SCO if the headset offers both.
      val device = available.firstOrNull { it.type == AudioDeviceInfo.TYPE_BLE_HEADSET }
        ?: available.firstOrNull { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }

      if (device == null) {
        notifyNone(listener)
      } else {
        waitForCommunicationDevice(device, listener)
        if (!audioManager.setCommunicationDevice(device)) {
          stopWaitingForCommunicationDevice()
          notifyNone(listener)
        }
      }
    } else {
      @Suppress("DEPRECATION")
      if (audioManager.isBluetoothScoOn()) {
        // Already up.
        startNotified = true
        listener?.onBlScoConnected()
      } else {
        audioManager.startBluetoothSco()
        // async — onBlScoConnected will be called via ACTION_SCO_AUDIO_STATE_UPDATED broadcast
      }
    }
  }

  // The link takes a moment to come up: a take started before it records the phone mic.
  @TargetApi(Build.VERSION_CODES.S)
  private fun waitForCommunicationDevice(device: AudioDeviceInfo, listener: BluetoothScoListener?) {
    stopWaitingForCommunicationDevice()
    // Already in use: no change is coming to wait for.
    if (audioManager.communicationDevice?.id == device.id) {
      startNotified = true
      listener?.onBlScoConnected()
      return
    }

    val onChanged =AudioManager.OnCommunicationDeviceChangedListener { current ->
      if (current?.id != device.id) return@OnCommunicationDeviceChangedListener
      stopWaitingForCommunicationDevice()
      startNotified = true
      listener?.onBlScoConnected()
    }
    communicationDeviceListener = onChanged
    audioManager.addOnCommunicationDeviceChangedListener({ handler.post(it) }, onChanged)
  }

  private fun stopWaitingForCommunicationDevice() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
    communicationDeviceListener?.let { audioManager.removeOnCommunicationDeviceChangedListener(it) }
    communicationDeviceListener = null
  }

  private fun notifyNone(listener: BluetoothScoListener?) {
    startNotified = true
    listener?.onBlScoNone()
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
