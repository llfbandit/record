package com.llfbandit.record.record.model

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaRecorder
import android.os.Build
import com.llfbandit.record.record.util.DeviceMapping
import com.llfbandit.record.record.util.InputDevices
import io.flutter.plugin.common.MethodCall

data class RecordConfig(
  val path: String?,
  val encoder: AudioEncoder,
  val bitRate: Int,
  val sampleRate: Int,
  val numChannels: Int,
  val device: AudioDeviceInfo?,
  val autoGain: Boolean = false,
  val echoCancel: Boolean = false,
  val noiseSuppress: Boolean = false,
  val useLegacy: Boolean = false,
  val muteAudio: Boolean = false,
  val manageBluetoothSco: Boolean = true,
  val audioSource: Int = MediaRecorder.AudioSource.DEFAULT,
  val speakerphone: Boolean = false,
  val audioManagerMode: Int = AudioManager.MODE_NORMAL,
  val audioInterruption: AudioInterruption = AudioInterruption.PAUSE,
  val audioRouteChange: AudioRouteChange = AudioRouteChange.PAUSE,
  val streamBufferSize: Int?,
  private val rawMap: Map<String, Any?> = emptyMap(),
  // Dart asked for a device that is not there. The take falls back to the default one.
  val deviceMissing: Boolean = false,
) {
  fun toMap(): Map<String, Any?> = rawMap + mapOf(
    "sampleRate" to sampleRate,
    "numChannels" to numChannels,
    "bitRate" to bitRate,
    // Report the device in use, not the requested one; null means the default device.
    "device" to device?.let { DeviceMapping.toMap(it) },
  )

  fun isModified(other: RecordConfig): Boolean =
    sampleRate != other.sampleRate ||
    numChannels != other.numChannels ||
    bitRate != other.bitRate

  companion object {
    fun fromMap(call: MethodCall, context: Context): RecordConfig {
      val rawMap = (call.arguments as Map<*, *>).entries
        .associate { (k, v) -> k.toString() to v }
      val map = call.argument("androidConfig") as Map<*, *>?
      val requestedDevice = call.argument<Map<String, String>>("device")
      val device = DeviceMapping.fromMap(InputDevices.list(context), requestedDevice)

      val audioSource: Int = when (map?.get("audioSource")) {
        "defaultSource" -> MediaRecorder.AudioSource.DEFAULT
        "mic" -> MediaRecorder.AudioSource.MIC
        "voiceUplink" -> MediaRecorder.AudioSource.VOICE_UPLINK
        "voiceDownlink" -> MediaRecorder.AudioSource.VOICE_DOWNLINK
        "voiceCall" -> MediaRecorder.AudioSource.VOICE_CALL
        "camcorder" -> MediaRecorder.AudioSource.CAMCORDER
        "voiceRecognition" -> MediaRecorder.AudioSource.VOICE_RECOGNITION
        "voiceCommunication" -> MediaRecorder.AudioSource.VOICE_COMMUNICATION
        "remoteSubMix" -> MediaRecorder.AudioSource.REMOTE_SUBMIX
        "unprocessed" -> MediaRecorder.AudioSource.UNPROCESSED
        "voicePerformance" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
          MediaRecorder.AudioSource.VOICE_PERFORMANCE
        } else {
          MediaRecorder.AudioSource.DEFAULT
        }

        else -> MediaRecorder.AudioSource.DEFAULT
      }

      val audioManagerMode: Int = when (map?.get("audioManagerMode")) {
        "modeNormal" -> AudioManager.MODE_NORMAL
        "modeRingtone" -> AudioManager.MODE_RINGTONE
        "modeInCall" -> AudioManager.MODE_IN_CALL
        "modeInCommunication" -> AudioManager.MODE_IN_COMMUNICATION
        "modeCallScreening" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
          AudioManager.MODE_CALL_SCREENING
        } else {
          AudioManager.MODE_NORMAL
        }

        "modeCallRedirect" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
          AudioManager.MODE_CALL_REDIRECT
        } else {
          AudioManager.MODE_NORMAL
        }

        "modeCommunicationRedirect" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
          AudioManager.MODE_COMMUNICATION_REDIRECT
        } else {
          AudioManager.MODE_NORMAL
        }

        else -> AudioManager.MODE_NORMAL
      }

      return RecordConfig(
        call.argument("path"),
        AudioEncoder.from(call.argument("encoder") ?: "aacLc"),
        call.argument("bitRate") ?: 128000,
        call.argument("sampleRate") ?: 44100,
        call.argument("numChannels") ?: 2,
        device,
        call.argument("autoGain") ?: false,
        call.argument("echoCancel") ?: false,
        call.argument("noiseSuppress") ?: false,
        map?.get("useLegacy") as Boolean? ?: false,
        map?.get("muteAudio") as Boolean? ?: false,
        map?.get("manageBluetooth") as Boolean? ?: true,
        audioSource,
        map?.get("speakerphone") as Boolean? ?: false,
        audioManagerMode,
        // Unknown index falls back to PAUSE.
        AudioInterruption.entries.getOrElse(call.argument("audioInterruption") ?: -1) { AudioInterruption.PAUSE },
        AudioRouteChange.entries.getOrElse(call.argument("audioRouteChange") ?: -1) { AudioRouteChange.PAUSE },
        call.argument("streamBufferSize"),
        rawMap,
        deviceMissing = requestedDevice != null && device == null,
      )
    }
  }
}

enum class AudioEncoder(val value: String) {
  AacLc("aacLc"),
  AacEld("aacEld"),
  AacHe("aacHe"),
  AmrNb("amrNb"),
  AmrWb("amrWb"),
  Flac("flac"),
  Pcm16bits("pcm16bits"),
  Opus("opus"),
  Wav("wav");

  companion object {
    fun fromOrNull(value: String?): AudioEncoder? = entries.firstOrNull { it.value == value }

    fun from(value: String): AudioEncoder = fromOrNull(value) ?: AacLc
  }
}

enum class AudioInterruption {
  NONE,
  PAUSE,
  PAUSE_RESUME
}

enum class AudioRouteChange {
  FOLLOW,
  PAUSE,
  STOP
}