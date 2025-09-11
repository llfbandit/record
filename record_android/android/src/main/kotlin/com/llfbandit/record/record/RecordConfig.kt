package com.llfbandit.record.record

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaRecorder
import android.os.Build
import com.llfbandit.record.Utils
import com.llfbandit.record.record.device.DeviceUtils
import io.flutter.plugin.common.MethodCall

class RecordConfig(
  val path: String?,
  encoder: String,
  val bitRate: Int,
  val sampleRate: Int,
  numChannels: Int,
  val device: AudioDeviceInfo?,
  val autoGain: Boolean = false,
  val echoCancel: Boolean = false,
  val noiseSuppress: Boolean = false,
  val useLegacy: Boolean = false,
  val service: AndroidService? = null,
  val muteAudio: Boolean = false,
  val manageBluetooth: Boolean = true,
  val audioSource: Int = MediaRecorder.AudioSource.DEFAULT,
  val speakerphone: Boolean = false,
  val audioManagerMode: Int = AudioManager.MODE_NORMAL,
  audioInterruption: Int,
  val streamBufferSize: Int?
) {
  val numChannels: Int = 2.coerceAtMost(1.coerceAtLeast(numChannels))
  val audioInterruption: AudioInterruption = when (audioInterruption) {
    0 -> AudioInterruption.NONE
    1 -> AudioInterruption.PAUSE
    2 -> AudioInterruption.PAUSE_RESUME
    else -> AudioInterruption.PAUSE
  }

  val encoder: AudioEncoder = when (encoder) {
    "aacLc" -> AudioEncoder.AacLc
    "aacEld" -> AudioEncoder.AacEld
    "aacHe" -> AudioEncoder.AacHe
    "amrNb" -> AudioEncoder.AmrNb
    "amrWb" -> AudioEncoder.AmrWb
    "flac" -> AudioEncoder.Flac
    "pcm16bits" -> AudioEncoder.Pcm16bits
    "opus" -> AudioEncoder.Opus
    "wav" -> AudioEncoder.Wav
    else -> AudioEncoder.AacLc
  }

  companion object {
    fun fromMap(call: MethodCall, context: Context): RecordConfig {
      val map = call.argument("androidConfig") as Map<*, *>?

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
        "unprocessed" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
          MediaRecorder.AudioSource.UNPROCESSED
        } else {
          MediaRecorder.AudioSource.DEFAULT
        }

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

      val serviceMap = map?.get("service") as Map<*, *>?
      val service = if (serviceMap != null) {
        AndroidService(serviceMap["title"] as String, serviceMap["content"] as String?)
      } else {
        null
      }

      return RecordConfig(
        call.argument("path"),
        Utils.firstNonNull(call.argument("encoder"), "aacLc"),
        Utils.firstNonNull(call.argument("bitRate"), 128000),
        Utils.firstNonNull(call.argument("sampleRate"), 44100),
        Utils.firstNonNull(call.argument("numChannels"), 2),
        DeviceUtils.deviceInfoFromMap(context, call.argument("device")),
        Utils.firstNonNull(call.argument("autoGain"), false),
        Utils.firstNonNull(call.argument("echoCancel"), false),
        Utils.firstNonNull(call.argument("noiseSuppress"), false),
        Utils.firstNonNull(map?.get("useLegacy") as Boolean?, false),
        service,
        Utils.firstNonNull(map?.get("muteAudio") as Boolean?, false),
        Utils.firstNonNull(map?.get("manageBluetooth") as Boolean?, true),
        audioSource,
        Utils.firstNonNull(map?.get("speakerphone") as Boolean?, false),
        audioManagerMode,
        Utils.firstNonNull(
          call.argument("audioInterruption"),
          AudioInterruption.PAUSE.ordinal
        ),
        call.argument("streamBufferSize")
      )
    }
  }
}

class AndroidService(
  val title: String,
  val content: String?,
)

enum class AudioEncoder(val value: String) {
  AacLc("aacLc"),
  AacEld("aacEld"),
  AacHe("aacHe"),
  AmrNb("amrNb"),
  AmrWb("amrWb"),
  Flac("flac"),
  Pcm16bits("pcm16bits"),
  Opus("opus"),
  Wav("wav")
}

enum class AudioInterruption {
  NONE,
  PAUSE,
  PAUSE_RESUME
}