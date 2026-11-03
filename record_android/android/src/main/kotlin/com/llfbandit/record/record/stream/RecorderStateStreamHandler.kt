package com.llfbandit.record.record.stream

import com.llfbandit.record.record.model.RecordState
import com.llfbandit.record.record.model.RecordStop
import com.llfbandit.record.record.util.MainThread
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink

class RecorderStateStreamHandler : EventChannel.StreamHandler {
  // Event producer
  private var eventSink: EventSink? = null

  override fun onListen(arguments: Any?, events: EventSink?) {
    this.eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  fun sendStateEvent(state: RecordState) {
    MainThread.post {
      eventSink?.success(state.id)
    }
  }

  fun sendStopEvent(stop: RecordStop) {
    val map = stop.toMap()

    MainThread.post {
      eventSink?.success(map)
    }
  }
}
