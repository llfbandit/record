package com.llfbandit.record.methodcall

import android.content.Context
import com.llfbandit.record.permission.PermissionManager
import com.llfbandit.record.record.RecordConfig
import com.llfbandit.record.record.device.DeviceUtils
import com.llfbandit.record.record.format.AudioFormats
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import java.util.Objects
import java.util.concurrent.ConcurrentHashMap

class MethodCallHandlerImpl(
  private val permissionManager: PermissionManager,
  private val messenger: BinaryMessenger,
  private val appContext: Context
) : MethodCallHandler {
  private val recorders = ConcurrentHashMap<String, RecorderWrapper>()

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    val recorderId = call.argument<String>("recorderId")

    if (recorderId.isNullOrEmpty()) {
      result.error("record", "Call missing mandatory parameter recorderId.", null)
      return
    }

    if (call.method == "create") {
      createRecorder(recorderId, result)
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
      "start" -> recorder.startRecordingToFile(RecordConfig.fromMap(call, appContext), result)
      "startStream" -> recorder.startRecordingToStream(RecordConfig.fromMap(call, appContext), result)
      "stop" -> recorder.stop(result)
      "pause" -> recorder.pause(result)
      "resume" -> recorder.resume(result)
      "isPaused" -> recorder.isPaused(result)
      "isRecording" -> recorder.isRecording(result)
      "cancel" -> recorder.cancel(result)
      "hasPermission" -> hasPermission(call, result)
      "getAmplitude" -> recorder.getAmplitude(result)
      "listInputDevices" -> result.success(DeviceUtils.listInputDevicesAsMap(appContext))
      "dispose" -> disposeRecorder(recorder, recorderId, result)
      "isEncoderSupported" -> isEncoderSupported(call, result)
      else -> result.notImplemented()
    }
  }

  fun dispose() {
    for (entry in recorders.entries) {
      disposeRecorder(entry.value, entry.key, null)
    }

    recorders.clear()
  }

  private fun createRecorder(recorderId: String, result: MethodChannel.Result) {
    try {
      val recorder = RecorderWrapper(appContext, recorderId, messenger)
      recorders[recorderId] = recorder
      result.success(null)
    } catch (e: Exception) {
      result.error("record", "Cannot create recorder.", e.message)
    }
  }

  private fun disposeRecorder(recorder: RecorderWrapper, recorderId: String, result: MethodChannel.Result?) {
    recorder.dispose()
    recorders.remove(recorderId)
    result?.success(null)
  }

  private fun hasPermission(call: MethodCall, result: MethodChannel.Result) {
    val request = call.argument<Boolean>("request") ?: true
    permissionManager.hasPermission(request, result::success)
  }

  private fun isEncoderSupported(call: MethodCall, result: MethodChannel.Result) {
    val codec = call.argument<String>("encoder")

    val isSupported = AudioFormats.isEncoderSupported(
      AudioFormats.getMimeType(Objects.requireNonNull(codec))
    )

    result.success(isSupported)
  }
}