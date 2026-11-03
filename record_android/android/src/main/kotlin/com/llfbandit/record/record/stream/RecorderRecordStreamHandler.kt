package com.llfbandit.record.record.stream

import com.llfbandit.record.record.util.MainThread
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink

class RecorderRecordStreamHandler : EventChannel.StreamHandler {
  // Event producer
  private var eventSink: EventSink? = null

  override fun onListen(arguments: Any?, events: EventSink?) {
    this.eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  fun sendRecordChunkEvent(buffer: ByteArray) {
    MainThread.post {
      eventSink?.success(buffer)
    }
  }

  /** Ends the Dart stream once a take is over; queued after its last chunk. */
  fun sendEndOfStream() {
    MainThread.post {
      eventSink?.endOfStream()
      eventSink = null
    }
  }
}
