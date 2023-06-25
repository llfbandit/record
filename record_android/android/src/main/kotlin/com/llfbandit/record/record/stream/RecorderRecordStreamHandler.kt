package com.llfbandit.record.record.stream

import android.app.Activity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink

class RecorderRecordStreamHandler : EventChannel.StreamHandler {
    // Event producer
    private var eventSink: EventSink? = null
    private var activity: Activity? = null

    override fun onListen(arguments: Any?, events: EventSink?) {
        this.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun sendRecordChunkEvent(buffer: ByteArray) {
        activity?.runOnUiThread {
            eventSink?.success(buffer)
        }
    }

    fun setActivity(activity: Activity?) {
        this.activity = activity
    }
}