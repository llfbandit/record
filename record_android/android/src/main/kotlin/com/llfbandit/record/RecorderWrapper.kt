package com.llfbandit.record

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.llfbandit.record.record.bluetooth.BluetoothManager
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.recorder.AudioRecorder
import com.llfbandit.record.record.recorder.IRecorder
import com.llfbandit.record.record.recorder.MediaRecorder
import com.llfbandit.record.record.stream.RecorderRecordStreamHandler
import com.llfbandit.record.record.stream.RecorderStateStreamHandler
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class RecorderWrapper(
  private val context: Context,
  recorderId: String,
  messenger: BinaryMessenger,
) {
  companion object {
    const val EVENTS_STATE_CHANNEL = "com.llfbandit.record/events/"
    const val EVENTS_RECORD_CHANNEL = "com.llfbandit.record/eventsRecord/"
    const val CONFIG_CHANGED_CHANNEL = "com.llfbandit.record/configChanged/"
    private val mainHandler = Handler(Looper.getMainLooper())
  }

  // Owns this recorder's control-plane thread; isolated from other recorders.
  private val dispatcher = RecorderDispatcher()
  private val handler = dispatcher.handler

  private var eventChannel: EventChannel?
  private val recorderStateStreamHandler = RecorderStateStreamHandler()
  private var eventRecordChannel: EventChannel?
  private val recorderRecordStreamHandler = RecorderRecordStreamHandler()
  private val configChangedChannel: MethodChannel
  private var recorder: IRecorder? = null
  private val bluetoothManager = BluetoothManager(context, handler)

  init {
    eventChannel = EventChannel(messenger, EVENTS_STATE_CHANNEL + recorderId)
    eventChannel?.setStreamHandler(recorderStateStreamHandler)
    eventRecordChannel = EventChannel(messenger, EVENTS_RECORD_CHANNEL + recorderId)
    eventRecordChannel?.setStreamHandler(recorderRecordStreamHandler)
    configChangedChannel = MethodChannel(messenger, CONFIG_CHANGED_CHANNEL + recorderId)
  }

  fun startRecordingToFile(config: RecordConfig, result: MethodChannel.Result) {
    dispatcher.post { startRecording(config, result) }
  }

  fun startRecordingToStream(config: RecordConfig, result: MethodChannel.Result) {
    if (config.useLegacy) {
      throw Exception("Cannot stream audio while using the legacy recorder")
    }
    dispatcher.post { startRecording(config, result) }
  }

  fun dispose() {
    dispatcher.post {
      try {
        recorder?.dispose()
      } catch (_: Exception) {
      } finally {
        bluetoothManager.stop()
        recorder = null
      }
    }
    // Queued work above still runs before quit() actually stops the thread.
    dispatcher.quit()

    // Channel (de)registration stays on the platform thread dispose() runs on.
    eventChannel?.setStreamHandler(null)
    eventChannel = null

    eventRecordChannel?.setStreamHandler(null)
    eventRecordChannel = null
  }

  fun pause(result: MethodChannel.Result) {
    dispatcher.post {
      try {
        recorder?.pause()
        result.success(null)
      } catch (e: Exception) {
        result.error("record", e.message, e.cause)
      }
    }
  }

  fun isPaused(result: MethodChannel.Result) {
    dispatcher.post { result.success(recorder?.isPaused ?: false) }
  }

  fun isRecording(result: MethodChannel.Result) {
    dispatcher.post { result.success(recorder?.isRecording ?: false) }
  }

  fun getAmplitude(result: MethodChannel.Result) {
    dispatcher.post {
      if (recorder != null) {
        val amps = recorder!!.getAmplitude()
        val amp: MutableMap<String, Any> = HashMap()
        amp["current"] = amps[0]
        amp["max"] = amps[1]
        result.success(amp)
      } else {
        result.success(null)
      }
    }
  }

  fun resume(result: MethodChannel.Result) {
    dispatcher.post {
      try {
        recorder?.resume()
        result.success(null)
      } catch (e: Exception) {
        result.error("record", e.message, e.cause)
      }
    }
  }

  fun stop(result: MethodChannel.Result) {
    dispatcher.post {
      try {
        if (recorder == null) {
          result.success(null)
        } else {
          recorder?.stop(fun(path) = result.success(path))
        }
      } catch (e: Exception) {
        result.error("record", e.message, e.cause)
      }
    }
  }

  fun cancel(result: MethodChannel.Result) {
    dispatcher.post {
      try {
        recorder?.cancel()
        result.success(null)
      } catch (e: Exception) {
        result.error("record", e.message, e.cause)
      }

      bluetoothManager.stop()
    }
  }

  private fun startRecording(config: RecordConfig, result: MethodChannel.Result) {
    try {
      if (recorder == null) {
        bluetoothManager.maybeStart(config) {
          recorder = createRecorder(config)
          start(config, result)
        }
      } else if (recorder!!.isRecording) {
        // stopCb may run on the dying recorder's own thread.
        recorder!!.stop(fun(_) = dispatcher.post {
          bluetoothManager.maybeStart(config) {
            start(config, result)
          }
        })
      } else {
        bluetoothManager.maybeStart(config) {
          start(config, result)
        }
      }
    } catch (e: Exception) {
      result.error("record", e.message, e.cause)
    }
  }

  private fun createRecorder(config: RecordConfig): IRecorder {
    if (config.useLegacy) {
      return MediaRecorder(context, recorderStateStreamHandler)
    }

    return AudioRecorder(
      recorderStateStreamHandler,
      recorderRecordStreamHandler,
      context,
      handler,
    )
  }

  private fun start(config: RecordConfig, result: MethodChannel.Result) {
    try {
      val orig = config.copy()
      recorder!!.start(config)
      result.success(null)
      if (config.isModified(orig)) notifyConfigChanged(config)
    } catch (e: Exception) {
      result.error("record", e.message, e.cause)
    }
  }

  // invokeMethod requires the platform thread; we're on the dispatcher thread here.
  private fun notifyConfigChanged(config: RecordConfig) {
    mainHandler.post {
      configChangedChannel.invokeMethod("onConfigChanged", config.toMap())
    }
  }
}
