package com.llfbandit.record

import android.content.Context
import com.llfbandit.record.permission.PermissionManager
import com.llfbandit.record.record.format.AudioFormats
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.util.DeviceUtils
import com.llfbandit.record.record.util.MainThread
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MethodCallHandlerImpl(
  private val permissionManager: PermissionManager,
  private val messenger: BinaryMessenger,
  private val appContext: Context,
) : MethodChannel.MethodCallHandler {
  private val recorders = HashMap<String, RecorderWrapper>()

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    val recorderId = call.argument<String>("recorderId")

    if (recorderId.isNullOrEmpty()) {
      result.error("record", "Call missing mandatory parameter recorderId.", null)
      return
    }

    // Stateless, or UI-bound (permission dialogs must run on the platform thread).
    when (call.method) {
      "hasPermission" -> { hasPermission(call, result); return }
      "listInputDevices" -> { result.success(DeviceUtils.listInputDevicesAsMap(appContext)); return }
      "isEncoderSupported" -> { isEncoderSupported(call, result); return }
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

    val mainResult = MainThreadResult(result)
    when (call.method) {
      "start" -> recorder.startRecordingToFile(RecordConfig.fromMap(call, appContext), mainResult)
      "startStream" -> recorder.startRecordingToStream(RecordConfig.fromMap(call, appContext), mainResult)
      "stop" -> recorder.stop(mainResult)
      "pause" -> recorder.pause(mainResult)
      "resume" -> recorder.resume(mainResult)
      "isPaused" -> recorder.isPaused(mainResult)
      "isRecording" -> recorder.isRecording(mainResult)
      "cancel" -> recorder.cancel(mainResult)
      "getAmplitude" -> recorder.getAmplitude(mainResult)
      "dispose" -> disposeRecorder(recorder, recorderId, mainResult)
      else -> result.notImplemented()
    }
  }

  fun dispose() {
    // Iterate a snapshot: disposeRecorder() mutates the backing map.
    for ((recorderId, recorder) in HashMap(recorders)) {
      disposeRecorder(recorder, recorderId, null)
    }
    recorders.clear()
  }

  // Marshals Result callbacks back to the platform thread Flutter requires.
  private class MainThreadResult(
    private val delegate: MethodChannel.Result
  ) : MethodChannel.Result {
    override fun success(result: Any?) { MainThread.post { delegate.success(result) } }
    override fun error(code: String, message: String?, details: Any?) {
      MainThread.post { delegate.error(code, message, details) }
    }
    override fun notImplemented() { MainThread.post { delegate.notImplemented() } }
  }

  private fun createRecorder(recorderId: String, result: MethodChannel.Result) {
    if (recorders.containsKey(recorderId)) {
      result.success(null)
      return
    }

    try {
      recorders[recorderId] = RecorderWrapper(appContext, recorderId, messenger)
      result.success(null)
    } catch (e: Exception) {
      result.error("record", "Cannot create recorder.", e.message)
    }
  }

  private fun disposeRecorder(recorder: RecorderWrapper, recorderId: String, result: MethodChannel.Result?) {
    recorder.dispose(result)
    recorders.remove(recorderId)
  }

  private fun hasPermission(call: MethodCall, result: MethodChannel.Result) {
    val request = call.argument<Boolean>("request") ?: true
    permissionManager.hasPermission(request, result::success)
  }

  private fun isEncoderSupported(call: MethodCall, result: MethodChannel.Result) {
    val codec = call.argument<String>("encoder")

    val isSupported = AudioFormats.isEncoderSupported(
      AudioFormats.getMimeType(codec)
    )

    result.success(isSupported)
  }
}