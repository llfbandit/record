package com.llfbandit.record.record.stream

import android.os.Handler
import android.os.Looper
import com.llfbandit.record.record.RecordState
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink

class RecorderStateStreamHandler : EventChannel.StreamHandler {
  // Event producer
  private var eventSink: EventSink? = null
  private var state: RecordState = RecordState.STOP

  private val uiThreadHandler = Handler(Looper.getMainLooper())

  override fun onListen(arguments: Any?, events: EventSink?) {
    this.eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  fun sendStateEvent(state: RecordState) {
    if (this.state != state) {
      this.state = state

      uiThreadHandler.post {
        eventSink?.success(state.id)
      }
    }
  }

  fun sendStateErrorEvent(ex: Exception) {
    uiThreadHandler.post {
      eventSink?.error("-1", ex.message, ex)
    }
  }
}