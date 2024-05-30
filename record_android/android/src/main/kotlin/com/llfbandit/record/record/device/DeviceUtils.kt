package com.llfbandit.record.record.device

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build

class DeviceUtils {
    companion object {
        fun listInputDevicesAsMap(context: Context): List<Map<String, String>> {
            val devices = listInputDevices(context).map {
                val label = StringBuilder()
                label.apply {
                    append(it.productName)
                    append(" (")
                    append(typeToString(it.type))
                    if (Build.VERSION.SDK_INT >= 28) append(", ${it.address}")
                    append(")")
                }

                mapOf(
                    "id" to "${it.id}",
                    "label" to label.toString(),
                )
            }

            return devices
        }

        private fun listInputDevices(context: Context): List<AudioDeviceInfo> {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val devices = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)

            return filterSources(devices.asList())
        }

        fun deviceInfoFromMap(context: Context, device: Map<String, String>?): AudioDeviceInfo? {
            if (device == null) return null

            return listInputDevices(context).firstOrNull {
                it.id.toString() == device["id"]
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

        private fun typeToString(type: Int): String {
            return when (type) {
                AudioDeviceInfo.TYPE_UNKNOWN -> "unknown"
                AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "built-in earpiece"
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "built-in speaker"
                AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wired headset"
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "wired headphones"
                AudioDeviceInfo.TYPE_LINE_ANALOG -> "line analog"
                AudioDeviceInfo.TYPE_LINE_DIGITAL -> "line digital"
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth telephony SCO"
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth A2DP"
                AudioDeviceInfo.TYPE_HDMI -> "HDMI"
                AudioDeviceInfo.TYPE_HDMI_ARC -> "HDMI audio return channel"
                AudioDeviceInfo.TYPE_USB_DEVICE -> "USB device"
                AudioDeviceInfo.TYPE_USB_ACCESSORY -> "USB accessory"
                AudioDeviceInfo.TYPE_DOCK -> "dock"
                AudioDeviceInfo.TYPE_FM -> "FM"
                AudioDeviceInfo.TYPE_BUILTIN_MIC -> "built-in microphone"
                AudioDeviceInfo.TYPE_FM_TUNER -> "FM tuner"
                AudioDeviceInfo.TYPE_TV_TUNER -> "TV tuner"
                AudioDeviceInfo.TYPE_TELEPHONY -> "telephony"
                AudioDeviceInfo.TYPE_AUX_LINE -> "auxiliary line-level connectors"
                AudioDeviceInfo.TYPE_IP -> "IP"
                AudioDeviceInfo.TYPE_BUS -> "bus"
                AudioDeviceInfo.TYPE_USB_HEADSET -> "USB headset"
                AudioDeviceInfo.TYPE_HEARING_AID -> "hearing aid"
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE -> "built-in speaker safe"
                AudioDeviceInfo.TYPE_REMOTE_SUBMIX -> "remote submix" // 25
                AudioDeviceInfo.TYPE_BLE_HEADSET -> "BLE headset"
                AudioDeviceInfo.TYPE_BLE_SPEAKER -> "BLE speaker"
                28 -> "echo reference" // AudioDeviceInfo.TYPE_ECHO_REFERENCE
                AudioDeviceInfo.TYPE_HDMI_EARC -> "HDMI enhanced ARC"
                AudioDeviceInfo.TYPE_BLE_BROADCAST -> "BLE broadcast"
                else -> "unknown=$type"
            }
        }
    }
}