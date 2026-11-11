package com.llfbandit.record.record.util

import android.media.AudioDeviceInfo
import android.os.Build

/** Converts input devices to and from what Dart sees. */
object DeviceMapping {
  /** The id Dart sees: type and address, which a re-plug keeps. Android's id without an address. */
  fun deviceId(device: AudioDeviceInfo): String {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || device.address.isEmpty()) return "${device.id}"
    return "${device.type}:${device.address}"
  }

  fun toMap(device: AudioDeviceInfo): Map<String, Any> {
    return mapOf(
      "id" to deviceId(device),
      "label" to device.productName,
      "type" to typeToInputDeviceType(device.type),
      "sampleRates" to device.sampleRates.toList(),
    )
  }

  /** Finds the device Dart sent among [inputs]. */
  fun fromMap(inputs: List<AudioDeviceInfo>, device: Map<String, String>?): AudioDeviceInfo? {
    val id = device?.get("id") ?: return null

    // Apps may have saved Android's id.
    return inputs.firstOrNull { deviceId(it) == id } ?: inputs.firstOrNull { "${it.id}" == id }
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
}
