package com.llfbandit.record.record.stream

import com.llfbandit.record.record.model.RecordState
import com.llfbandit.record.record.util.MainThread
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink

class RecorderStateStreamHandler : EventChannel.StreamHandler {
  // Event producer
  private var eventSink: EventSink? = null
  private var state: RecordState = RecordState.STOP

  override fun onListen(arguments: Any?, events: EventSink?) {
    this.eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  fun sendStateEvent(state: RecordState) {
    if (this.state != state) {
      this.state = state

      MainThread.post {
        eventSink?.success(state.id)
      }
    }
  }

  fun sendStateErrorEvent(ex: Exception) {
    MainThread.post {
      // `details` must be codec-encodable; a Throwable is not.
      eventSink?.error("-1", ex.message ?: ex.toString(), ex.cause?.toString())
    }
  }
}
