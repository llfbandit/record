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
  private var onReady: (() -> Unit)? = null
  private val devices = HashSet<AudioDeviceInfo>()
  private var audioDeviceCallback: AudioDeviceCallback? = null
  private var mRegistered: Boolean = false
  private var startNotified: Boolean = false
  private var communicationDeviceListener: AudioManager.OnCommunicationDeviceChangedListener? = null

  init {
    filter.addAction(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
  }

  fun register(onReady: () -> Unit) {
    context.registerReceiver(this, filter, null, handler)
    mRegistered = true

    this.onReady = onReady

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
    maybeStartOrNotify()
  }

  fun unregister() {
    stopWaitingForCommunicationDevice()
    stopBluetoothSco()

    if (audioDeviceCallback != null) {
      audioManager.unregisterAudioDeviceCallback(audioDeviceCallback)
      audioDeviceCallback = null
    }

    onReady = null
    startNotified = false

    if (mRegistered) {
      context.unregisterReceiver(this)
      mRegistered = false
    }
  }

  private fun maybeStartOrNotify() {
    val hasBluetoothSco = devices.any { isBluetoothHeadset(it.type) }
    if (hasBluetoothSco && audioManager.isBluetoothScoAvailableOffCall) {
      startBluetoothSco()
    } else {
      // Stays registered, so another app's later SCO link must not look like ours starting.
      notifyReady()
    }
  }

  override fun onReceive(context: Context, intent: Intent) {
    val state = intent.getIntExtra(AudioManager.EXTRA_SCO_AUDIO_STATE, Int.MIN_VALUE)
    when (state) {
      // No connect will follow; answer now.
      AudioManager.SCO_AUDIO_STATE_CONNECTED,
      AudioManager.SCO_AUDIO_STATE_ERROR -> if (!startNotified) notifyReady()
    }
  }

  // Every path must notify: prepare() waits on this.
  private fun startBluetoothSco() {
    if (!audioManager.isBluetoothScoAvailableOffCall) {
      notifyReady()
      return
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      val available = audioManager.availableCommunicationDevices
      // LE Audio wins over SCO if the headset offers both.
      val device = available.firstOrNull { it.type == AudioDeviceInfo.TYPE_BLE_HEADSET }
        ?: available.firstOrNull { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }

      if (device == null) {
        notifyReady()
      } else {
        waitForCommunicationDevice(device)
        if (!audioManager.setCommunicationDevice(device)) {
          stopWaitingForCommunicationDevice()
          notifyReady()
        }
      }
    } else {
      @Suppress("DEPRECATION")
      if (audioManager.isBluetoothScoOn()) {
        // Already up.
        notifyReady()
      } else {
        audioManager.startBluetoothSco()
        // async — notifyReady() will be called via ACTION_SCO_AUDIO_STATE_UPDATED broadcast
      }
    }
  }

  // The link takes a moment to come up: a take started before it records the phone mic.
  @TargetApi(Build.VERSION_CODES.S)
  private fun waitForCommunicationDevice(device: AudioDeviceInfo) {
    stopWaitingForCommunicationDevice()
    // Already in use: no change is coming to wait for.
    if (audioManager.communicationDevice?.id == device.id) {
      notifyReady()
      return
    }

    val onChanged =AudioManager.OnCommunicationDeviceChangedListener { current ->
      if (current?.id != device.id) return@OnCommunicationDeviceChangedListener
      stopWaitingForCommunicationDevice()
      notifyReady()
    }
    communicationDeviceListener = onChanged
    audioManager.addOnCommunicationDeviceChangedListener({ handler.post(it) }, onChanged)
  }

  private fun stopWaitingForCommunicationDevice() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
    communicationDeviceListener?.let { audioManager.removeOnCommunicationDeviceChangedListener(it) }
    communicationDeviceListener = null
  }

  private fun notifyReady() {
    startNotified = true
    onReady?.invoke()
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
