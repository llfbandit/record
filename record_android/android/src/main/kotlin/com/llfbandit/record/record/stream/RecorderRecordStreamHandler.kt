package com.llfbandit.record.record.stream

import android.app.Activity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import android.os.Handler
import android.os.Looper

class RecorderRecordStreamHandler : EventChannel.StreamHandler {
    // Event producer
    private var eventSink: EventSink? = null
    private var activity: Activity? = null

    private val uiThreadHandler = Handler(Looper.getMainLooper())

    override fun onListen(arguments: Any?, events: EventSink?) {
        this.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun sendRecordChunkEvent(buffer: ByteArray) {
        uiThreadHandler.post(Runnable {
            eventSink?.success(buffer)
        })
    }

    fun setActivity(activity: Activity?) {
        this.activity = activity
    }
}