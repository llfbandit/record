package com.llfbandit.record

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.llfbandit.record.permission.PermissionManager
import com.llfbandit.record.record.format.AudioFormats
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.util.DeviceUtils
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutionException

class MethodCallHandlerImpl(
  private val permissionManager: PermissionManager,
  private val messenger: BinaryMessenger,
  private val appContext: Context
) : MethodChannel.MethodCallHandler {
  private data class RecorderEntry(
    val recorder: RecorderWrapper,
    val calls: RecorderCallQueue
  )

  private val recorders = ConcurrentHashMap<String, RecorderEntry>()
  private val disposingRecorders = ConcurrentHashMap<String, RecorderEntry>()
  private val uiThreadHandler = Handler(Looper.getMainLooper())
  private var disposed = false

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

    val entry = recorders[recorderId]
    if (entry == null) {
      result.error(
        "record",
        "Recorder has not yet been created or has already been disposed.", null
      )
      return
    }

    when (call.method) {
      "start" -> dispatch(entry, result) {
        entry.recorder.startRecordingToFile(RecordConfig.fromMap(call, appContext), result)
      }
      "startStream" -> dispatch(entry, result) {
        entry.recorder.startRecordingToStream(RecordConfig.fromMap(call, appContext), result)
      }
      "stop" -> dispatch(entry, result) { entry.recorder.stop(result) }
      "pause" -> dispatch(entry, result) { entry.recorder.pause(result) }
      "resume" -> dispatch(entry, result) { entry.recorder.resume(result) }
      "isPaused" -> dispatch(entry, result) { entry.recorder.isPaused(result) }
      "isRecording" -> dispatch(entry, result) { entry.recorder.isRecording(result) }
      "cancel" -> dispatch(entry, result) { entry.recorder.cancel(result) }
      "hasPermission" -> hasPermission(call, result)
      "getAmplitude" -> dispatch(entry, result) { entry.recorder.getAmplitude(result) }
      "listInputDevices" -> dispatch(entry, result) {
        result.success(DeviceUtils.listInputDevicesAsMap(appContext))
      }
      "dispose" -> disposeRecorder(entry, recorderId, result)
      "isEncoderSupported" -> dispatch(entry, result) { isEncoderSupported(call, result) }
      else -> result.notImplemented()
    }
  }

  fun dispose() {
    disposed = true
    val entries = (recorders.values + disposingRecorders.values).distinct()
    recorders.clear()
    disposingRecorders.clear()

    val cleanupFutures = entries.map { entry ->
      entry.calls.close { entry.recorder.disposeRecorder() }
    }

    var interrupted = false
    for (future in cleanupFutures) {
      while (true) {
        try {
          future.get()
          break
        } catch (e: InterruptedException) {
          interrupted = true
          Log.w(TAG, "Interrupted while disposing recorder", e)
        } catch (e: ExecutionException) {
          Log.w(TAG, "Failed to dispose recorder", e.cause)
          break
        }
      }
    }

    entries.forEach { it.recorder.detachChannels() }
    if (interrupted) Thread.currentThread().interrupt()
  }

  private fun createRecorder(recorderId: String, result: MethodChannel.Result) {
    if (recorders.containsKey(recorderId) || disposingRecorders.containsKey(recorderId)) {
      result.error("record", "Recorder has already been created or is being disposed.", null)
      return
    }

    try {
      val calls = RecorderCallQueue("RecordMethodCall-$recorderId")
      val recorder = RecorderWrapper(appContext, recorderId, messenger, calls::executeOrRun)
      recorders[recorderId] = RecorderEntry(recorder, calls)
      result.success(null)
    } catch (e: Exception) {
      result.error("record", "Cannot create recorder.", e.message)
    }
  }

  private fun dispatch(
    entry: RecorderEntry,
    result: MethodChannel.Result,
    call: () -> Unit
  ) {
    val accepted = entry.calls.execute {
      try {
        call()
      } catch (e: Exception) {
        result.error("record", e.message, e.cause)
      }
    }

    if (!accepted) {
      result.error(
        "record",
        "Recorder has not yet been created or has already been disposed.",
        null
      )
    }
  }

  private fun disposeRecorder(
    entry: RecorderEntry,
    recorderId: String,
    result: MethodChannel.Result?
  ) {
    if (!recorders.remove(recorderId, entry)) {
      result?.error(
        "record",
        "Recorder has not yet been created or has already been disposed.",
        null
      )
      return
    }

    disposingRecorders[recorderId] = entry
    entry.calls.close {
      try {
        entry.recorder.disposeRecorder()
      } finally {
        uiThreadHandler.post {
          if (!disposed) {
            entry.recorder.detachChannels()
            disposingRecorders.remove(recorderId, entry)
            result?.success(null)
          } else {
            disposingRecorders.remove(recorderId, entry)
          }
        }
      }
    }
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

  companion object {
    private const val TAG = "RecordPlugin"
  }
}
