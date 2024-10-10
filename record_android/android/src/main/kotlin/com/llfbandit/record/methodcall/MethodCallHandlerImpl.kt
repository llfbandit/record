package com.llfbandit.record.methodcall

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import com.llfbandit.record.Utils
import com.llfbandit.record.permission.PermissionManager
import com.llfbandit.record.record.RecordConfig
import com.llfbandit.record.record.device.DeviceUtils
import com.llfbandit.record.record.format.AudioFormats
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import java.io.IOException
import java.util.Objects
import java.util.concurrent.ConcurrentHashMap

class MethodCallHandlerImpl(
    private val permissionManager: PermissionManager,
    private val messenger: BinaryMessenger,
    private val appContext: Context
) : MethodCallHandler {
    private val recorders = ConcurrentHashMap<String, RecorderWrapper>()


    fun dispose() {
        for (entry in recorders.entries) {
            disposeRecorder(entry.value, entry.key)
        }

        recorders.clear()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val recorderId = call.argument<String>("recorderId")

        if (recorderId.isNullOrEmpty()) {
            result.error("record", "Call missing mandatory parameter recorderId.", null)
            return
        }

        if (call.method == "create") {
            try {
                createRecorder(recorderId)
                result.success(null)
            } catch (e: Exception) {
                result.error("record", "Cannot create recording configuration.", e.message)
            }
            return
        }

        val recorder = recorders[recorderId]
        if (recorder == null) {
            result.error(
                "record",
                "Recorder has not yet been created or has already been disposed.", null
            )
            return
        }

        when (call.method) {
            "start" -> {
                try {
                    val config = getRecordConfig(call)
                    recorder.startRecordingToFile(config, result)
                } catch (e: IOException) {
                    result.error("record", "Cannot create recording configuration.", e.message)
                }
            }

            "startStream" -> {
                try {
                    val config = getRecordConfig(call)
                    recorder.startRecordingToStream(config, result)
                } catch (e: IOException) {
                    result.error("record", "Cannot create recording configuration.", e.message)
                }
            }

            "stop" -> recorder.stop(result)
            "pause" -> recorder.pause(result)
            "resume" -> recorder.resume(result)
            "isPaused" -> recorder.isPaused(result)
            "isRecording" -> recorder.isRecording(result)
            "cancel" -> recorder.cancel(result)
            "hasPermission" -> permissionManager.hasPermission(result::success)
            "getAmplitude" -> recorder.getAmplitude(result)
            "listInputDevices" -> result.success(DeviceUtils.listInputDevicesAsMap(appContext))

            "dispose" -> {
                disposeRecorder(recorder, recorderId)
                result.success(null)
            }

            "isEncoderSupported" -> {
                val codec = call.argument<String>("encoder")
                val isSupported = AudioFormats.isEncoderSupported(
                    AudioFormats.getMimeType(Objects.requireNonNull(codec))
                )
                result.success(isSupported)
            }

            else -> result.notImplemented()
        }
    }

    private fun createRecorder(recorderId: String) {
        val recorder = RecorderWrapper(appContext, recorderId, messenger)
        recorders[recorderId] = recorder
    }

    private fun disposeRecorder(recorder: RecorderWrapper, recorderId: String) {
        recorder.dispose()
        recorders.remove(recorderId)
    }

    private fun getRecordConfig(call: MethodCall): RecordConfig {
        val androidConfig = call.argument("androidConfig") as Map<*, *>?

        val audioSource: Int = when(androidConfig?.get("audioSource")) {
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

        return RecordConfig(
            call.argument("path"),
            Utils.firstNonNull(call.argument("encoder"), "aacLc"),
            Utils.firstNonNull(call.argument("bitRate"), 128000),
            Utils.firstNonNull(call.argument("sampleRate"), 44100),
            Utils.firstNonNull(call.argument("numChannels"), 2),
            DeviceUtils.deviceInfoFromMap(appContext, call.argument("device")),
            Utils.firstNonNull(call.argument("autoGain"), false),
            Utils.firstNonNull(call.argument("echoCancel"), false),
            Utils.firstNonNull(call.argument("noiseSuppress"), false),
            Utils.firstNonNull(androidConfig?.get("useLegacy") as Boolean?, false),
            Utils.firstNonNull(androidConfig?.get("muteAudio") as Boolean?, false),
            Utils.firstNonNull(androidConfig?.get("manageBluetooth") as Boolean?, true),
            audioSource
        )
    }
}