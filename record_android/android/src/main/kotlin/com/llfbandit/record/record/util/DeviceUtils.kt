package com.llfbandit.record.record.util

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build

class DeviceUtils {
  companion object {
    fun listInputDevicesAsMap(context: Context): List<Map<String, Any>> {
      return listInputDevices(context).map { deviceInfoToMap(it) }
    }

    fun hasInputDevices(context: Context): Boolean = listInputDevices(context).isNotEmpty()

    /** Finds [device] among current inputs by id, or by type and address after a re-plug changed its id. */
    fun findInputDevice(context: Context, device: AudioDeviceInfo): AudioDeviceInfo? {
      val inputs = listInputDevices(context)
      inputs.firstOrNull { it.id == device.id }?.let { return it }

      // The address only exists from API 28; an empty one could match any device of the type.
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || device.address.isEmpty()) return null
      return inputs.firstOrNull { it.type == device.type && it.address == device.address }
    }

    /** Calls [onRemoved] with the ids of input devices as they are unplugged, until closed. */
    fun watchInputRemovals(context: Context, onRemoved: (deviceIds: List<Int>) -> Unit): AutoCloseable {
      val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
      val callback = object : AudioDeviceCallback() {
        override fun onAudioDevicesRemoved(removedDevices: Array<AudioDeviceInfo>) {
          onRemoved(removedDevices.filter { it.isSource }.map { it.id })
        }
      }
      // With no handler, Android calls [onRemoved] on the main thread.
      audioManager.registerAudioDeviceCallback(callback, null)
      return AutoCloseable { audioManager.unregisterAudioDeviceCallback(callback) }
    }

    private fun listInputDevices(context: Context): List<AudioDeviceInfo> {
      val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
      val devices = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)

      return filterSources(devices.asList())
    }

    fun deviceInfoToMap(device: AudioDeviceInfo): Map<String, Any> {
      return mapOf(
        "id" to "${device.id}",
        "label" to device.productName,
        "type" to typeToInputDeviceType(device.type),
        "sampleRates" to device.sampleRates.toList(),
      )
    }

    private fun typeToInputDeviceType(type: Int): String {
      return when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_MIC -> "builtIn"
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wiredHeadset"
        AudioDeviceInfo.TYPE_LINE_ANALOG,
        AudioDeviceInfo.TYPE_LINE_DIGITAL,
        AudioDeviceInfo.TYPE_AUX_LINE -> "lineIn"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetoothSco"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bluetoothA2dp"
        AudioDeviceInfo.TYPE_BLE_HEADSET,
        AudioDeviceInfo.TYPE_BLE_SPEAKER,
        AudioDeviceInfo.TYPE_BLE_BROADCAST -> "bluetoothLe"
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_ACCESSORY,
        AudioDeviceInfo.TYPE_USB_HEADSET -> "usb"
        AudioDeviceInfo.TYPE_HDMI,
        AudioDeviceInfo.TYPE_HDMI_ARC,
        AudioDeviceInfo.TYPE_HDMI_EARC -> "hdmi"
        else -> "unknown"
      }
    }

    fun deviceInfoFromMap(context: Context, device: Map<String, String>?): AudioDeviceInfo? {
      if (device == null) return null

      return listInputDevices(context).firstOrNull {
        it.id.toString() == device["id"]
      }
    }

    @SuppressLint("MissingPermission")
    fun getDefaultInputDevice(): AudioDeviceInfo? {
      val channelConfig = AudioFormat.CHANNEL_IN_MONO
      val audioFormat = AudioFormat.ENCODING_PCM_16BIT
      val sampleRate = 8000
      val bufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
      if (bufferSize <= 0) return null

      val probe = try {
        AudioRecord(
          MediaRecorder.AudioSource.DEFAULT,
          sampleRate, channelConfig, audioFormat, bufferSize
        )
      } catch (_: Exception) {
        return null
      }

      if (probe.state != AudioRecord.STATE_INITIALIZED) {
        probe.release()
        return null
      }

      return try {
        probe.startRecording()
        probe.routedDevice
      } catch (_: Exception) {
        null
      } finally {
        try { probe.stop() } catch (_: Exception) {}
        probe.release()
      }
    }

    fun filterSources(devices: List<AudioDeviceInfo>): List<AudioDeviceInfo> {
      return devices.filter {
        it.isSource
          && it.type != 18 // TYPE_TELEPHONY
          && it.type != 25 // TYPE_REMOTE_SUBMIX
          && it.type != 28 // TYPE_ECHO_REFERENCE
      }
    }
  }
}