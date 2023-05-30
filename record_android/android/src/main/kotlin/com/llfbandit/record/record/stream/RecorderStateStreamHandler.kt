package com.llfbandit.record.record.stream

import android.app.Activity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink

class RecorderStateStreamHandler : EventChannel.StreamHandler {
    // Event producer
    private var eventSink: EventSink? = null
    private var activity: Activity? = null

    override fun onListen(arguments: Any?, events: EventSink?) {
        this.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun sendStateEvent(state: Int) {
        activity?.runOnUiThread {
            eventSink?.success(state)
        }
    }

    fun sendStateErrorEvent(ex: Exception) {
        activity?.runOnUiThread {
            eventSink?.error("-1", ex.message, ex)
        }
    }

    fun setActivity(activity: Activity?) {
        this.activity = activity
    }
}