package com.llfbandit.record.methodcall

import android.content.Context
import android.media.AudioDeviceInfo
import com.llfbandit.record.record.RecordConfig
import com.llfbandit.record.record.bluetooth.BluetoothReceiver
import com.llfbandit.record.record.bluetooth.BluetoothScoListener
import com.llfbandit.record.record.recorder.AudioRecorder
import com.llfbandit.record.record.recorder.IRecorder
import com.llfbandit.record.record.recorder.MediaRecorder
import com.llfbandit.record.record.stream.RecorderRecordStreamHandler
import com.llfbandit.record.record.stream.RecorderStateStreamHandler
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

internal class RecorderWrapper(
    private val context: Context,
    recorderId: String,
    messenger: BinaryMessenger
) : BluetoothScoListener {
    companion object {
        const val EVENTS_STATE_CHANNEL = "com.llfbandit.record/events/"
        const val EVENTS_RECORD_CHANNEL = "com.llfbandit.record/eventsRecord/"
    }

    private var eventChannel: EventChannel?
    private val recorderStateStreamHandler = RecorderStateStreamHandler()
    private var eventRecordChannel: EventChannel?
    private val recorderRecordStreamHandler = RecorderRecordStreamHandler()
    private var recorder: IRecorder? = null
    private var bluetoothReceiver: BluetoothReceiver? = null

    init {
        eventChannel = EventChannel(messenger, EVENTS_STATE_CHANNEL + recorderId)
        eventChannel?.setStreamHandler(recorderStateStreamHandler)
        eventRecordChannel = EventChannel(messenger, EVENTS_RECORD_CHANNEL + recorderId)
        eventRecordChannel?.setStreamHandler(recorderRecordStreamHandler)
    }

    fun startRecordingToFile(config: RecordConfig, result: MethodChannel.Result) {
        startRecording(config, result)
    }

    fun startRecordingToStream(config: RecordConfig, result: MethodChannel.Result) {
        if (config.useLegacy) {
            throw Exception("Cannot stream audio while using the legacy recorder")
        }
        startRecording(config, result)
    }

    fun dispose() {
        try {
            recorder?.dispose()
        } catch (ignored: Exception) {
        } finally {
            maybeStopBluetooth()
            recorder = null
        }

        eventChannel?.setStreamHandler(null)
        eventChannel = null

        eventRecordChannel?.setStreamHandler(null)
        eventRecordChannel = null
    }

    fun pause(result: MethodChannel.Result) {
        try {
            recorder?.pause()
            result.success(null)
        } catch (e: Exception) {
            result.error("record", e.message, e.cause)
        }
    }

    fun isPaused(result: MethodChannel.Result) {
        result.success(recorder?.isPaused ?: false)
    }

    fun isRecording(result: MethodChannel.Result) {
        result.success(recorder?.isRecording ?: false)
    }

    fun getAmplitude(result: MethodChannel.Result) {
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

    fun resume(result: MethodChannel.Result) {
        try {
            recorder?.resume()
            result.success(null)
        } catch (e: Exception) {
            result.error("record", e.message, e.cause)
        }
    }

    fun stop(result: MethodChannel.Result) {
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

    fun cancel(result: MethodChannel.Result) {
        try {
            recorder?.cancel()
            result.success(null)
        } catch (e: Exception) {
            result.error("record", e.message, e.cause)
        }

        maybeStopBluetooth()
    }

    private fun startRecording(config: RecordConfig, result: MethodChannel.Result) {
        try {
            if (recorder == null) {
                recorder = createRecorder(config)
                start(config, result)
            } else if (recorder!!.isRecording) {
                recorder!!.stop(fun(_) = start(config, result))
            } else {
                start(config, result)
            }
        } catch (e: Exception) {
            result.error("record", e.message, e.cause)
        }
    }

    private fun createRecorder(config: RecordConfig): IRecorder {
        if (config.manageBluetooth) {
            maybeStartBluetooth(config)
        }

        if (config.useLegacy) {
            return MediaRecorder(context, recorderStateStreamHandler)
        }

        return AudioRecorder(
            recorderStateStreamHandler,
            recorderRecordStreamHandler,
            context
        )
    }

    private fun start(config: RecordConfig, result: MethodChannel.Result) {
        recorder!!.start(config)
        result.success(null)
    }

    ///////////////////////////////////////////////////////////
    // Bluetooth SCO
    ///////////////////////////////////////////////////////////
    private fun maybeStartBluetooth(config: RecordConfig) {
        if (config.device != null && config.device.type != AudioDeviceInfo.TYPE_BLUETOOTH_SCO) {
            maybeStopBluetooth()
            return
        }

        if (bluetoothReceiver == null) {
            bluetoothReceiver = BluetoothReceiver(context)
        }

        if (!bluetoothReceiver!!.hasListeners()) {
            bluetoothReceiver!!.register()
            bluetoothReceiver!!.addListener(this)
        }
    }

    private fun maybeStopBluetooth() {
        bluetoothReceiver?.removeListener(this)

        if (bluetoothReceiver?.hasListeners() != true) {
            bluetoothReceiver?.unregister()
        }
    }

    override fun onBlScoConnected() {
    }

    override fun onBlScoDisconnected() {
    }
}
