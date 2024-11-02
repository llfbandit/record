package com.llfbandit.record.record.bluetooth

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import com.llfbandit.record.record.device.DeviceUtils

interface BluetoothScoListener {
    fun onBlScoConnected()
    fun onBlScoDisconnected()
}

class BluetoothReceiver(
    private val context: Context,
) : BroadcastReceiver() {
    private val filter = IntentFilter()
    private val audioManager: AudioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val listeners = HashSet<BluetoothScoListener>()
    private val devices = HashSet<AudioDeviceInfo>()
    private var audioDeviceCallback: AudioDeviceCallback? = null
    private var mRegistered: Boolean = false

    init {
        filter.addAction(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
    }

    fun hasListeners(): Boolean {
        return listeners.isNotEmpty()
    }

    fun register() {
        context.registerReceiver(this, filter)
        mRegistered = true

        audioDeviceCallback = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<AudioDeviceInfo>) {
                devices.addAll(DeviceUtils.filterSources(addedDevices.asList()))

                val hasBluetoothSco = devices.any {
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
                }
                if (hasBluetoothSco) {
                    startBluetooth()
                }
            }

            override fun onAudioDevicesRemoved(removedDevices: Array<AudioDeviceInfo>) {
                devices.removeAll(DeviceUtils.filterSources(removedDevices.asList()).toSet())

                val hasBluetoothSco = devices.any {
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
                }
                if (!hasBluetoothSco) {
                    stopBluetooth()
                }
            }
        }

        audioManager.registerAudioDeviceCallback(audioDeviceCallback, null)
    }

    fun unregister() {
        stopBluetooth()

        if (audioDeviceCallback != null) {
            audioManager.unregisterAudioDeviceCallback(audioDeviceCallback)
            audioDeviceCallback = null
        }

        listeners.clear()

        if (mRegistered) {
            context.unregisterReceiver(this)
            mRegistered = false
        }
    }

    fun addListener(listener: BluetoothScoListener) {
        listeners.add(listener)
    }

    fun removeListener(listener: BluetoothScoListener) {
        listeners.remove(listener)
    }

    override fun onReceive(context: Context, intent: Intent) {
        val state = intent.getIntExtra(AudioManager.EXTRA_SCO_AUDIO_STATE, -1)
        when (state) {
            AudioManager.SCO_AUDIO_STATE_CONNECTED -> listeners.forEach { it.onBlScoConnected() }
            AudioManager.SCO_AUDIO_STATE_DISCONNECTED -> listeners.forEach { it.onBlScoDisconnected() }
        }
    }

    @Suppress("DEPRECATION")
    fun startBluetooth(): Boolean {
        if (!audioManager.isBluetoothScoAvailableOffCall) {
            return false
        }

        if (!audioManager.isBluetoothScoOn()) {
            audioManager.startBluetoothSco()
        }

        return true
    }

    @Suppress("DEPRECATION")
    fun stopBluetooth() {
        if (audioManager.isBluetoothScoOn()) {
            audioManager.stopBluetoothSco()
        }
    }
}

