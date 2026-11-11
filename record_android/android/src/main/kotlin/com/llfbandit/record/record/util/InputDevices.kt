package com.llfbandit.record.record.util

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler

/** The input devices Android can record from. */
object InputDevices {
  fun list(context: Context): List<AudioDeviceInfo> {
    val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val devices = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)

    return filterSources(devices.asList())
  }

  fun hasAny(context: Context): Boolean = list(context).isNotEmpty()

  /** Finds [device] among current inputs, even after a re-plug. */
  fun find(context: Context, device: AudioDeviceInfo): AudioDeviceInfo? {
    val inputs = list(context)
    return inputs.firstOrNull { it.id == device.id }
      ?: inputs.firstOrNull { DeviceMapping.deviceId(it) == DeviceMapping.deviceId(device) }
  }

  /** Calls [onRemoved] with the ids of input devices as they are unplugged, until closed. */
  fun watchRemovals(
    context: Context,
    handler: Handler,
    onRemoved: (deviceIds: List<Int>) -> Unit,
  ): AutoCloseable {
    val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val callback = object : AudioDeviceCallback() {
      override fun onAudioDevicesRemoved(removedDevices: Array<AudioDeviceInfo>) {
        onRemoved(filterSources(removedDevices.asList()).map { it.id })
      }
    }
    audioManager.registerAudioDeviceCallback(callback, handler)
    return AutoCloseable { audioManager.unregisterAudioDeviceCallback(callback) }
  }

  /** The device Android records from when none is selected. */
  @SuppressLint("MissingPermission")
  fun default(): AudioDeviceInfo? {
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
        && it.type != AudioDeviceInfo.TYPE_TELEPHONY
        && it.type != AudioDeviceInfo.TYPE_REMOTE_SUBMIX
        && it.type != TYPE_ECHO_REFERENCE
    }
  }

  // AudioDeviceInfo.TYPE_ECHO_REFERENCE is a system API, so apps can't reference it.
  private const val TYPE_ECHO_REFERENCE = 28
}
