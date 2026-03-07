package com.llfbandit.record.methodcall

import android.content.Context
import android.os.Handler
import android.os.Looper
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
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MethodCallHandlerImpl(
  private val permissionManager: PermissionManager,
  private val messenger: BinaryMessenger,
  private val appContext: Context
) : MethodCallHandler {
  private val recorders = ConcurrentHashMap<String, RecorderWrapper>()
  private val uiThreadHandler = Handler(Looper.getMainLooper())
  private val startExecutor: ExecutorService = Executors.newSingleThreadExecutor()

  fun dispose() {
    for (entry in recorders.entries) {
      disposeRecorder(entry.value, entry.key)
    }

    recorders.clear()
    startExecutor.shutdownNow()
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
      "start" -> startExecutor.execute {
        try {
          val config = RecordConfig.fromMap(call, appContext)
          recorder.startRecordingToFile(config, MainThreadResult(result))
        } catch (e: IOException) {
          MainThreadResult(result).error(
            "record",
            "Cannot create recording configuration.",
            e.message
          )
        }
      }

      "startStream" -> startExecutor.execute {
        try {
          val config = RecordConfig.fromMap(call, appContext)
          recorder.startRecordingToStream(config, MainThreadResult(result))
        } catch (e: IOException) {
          MainThreadResult(result).error(
            "record",
            "Cannot create recording configuration.",
            e.message
          )
        }
      }

      "stop" -> recorder.stop(result)
      "pause" -> recorder.pause(result)
      "resume" -> recorder.resume(result)
      "isPaused" -> recorder.isPaused(result)
      "isRecording" -> recorder.isRecording(result)
      "cancel" -> recorder.cancel(result)
      "hasPermission" -> {
        val request = call.argument<Boolean>("request") ?: true
        permissionManager.hasPermission(request, result::success)
      }
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

  private inner class MainThreadResult(
    private val delegate: MethodChannel.Result
  ) : MethodChannel.Result {
    override fun success(result: Any?) {
      uiThreadHandler.post { delegate.success(result) }
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
      uiThreadHandler.post { delegate.error(errorCode, errorMessage, errorDetails) }
    }

    override fun notImplemented() {
      uiThreadHandler.post { delegate.notImplemented() }
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
}