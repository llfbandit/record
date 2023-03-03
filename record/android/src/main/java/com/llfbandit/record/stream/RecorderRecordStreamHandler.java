package com.llfbandit.record.stream;

import io.flutter.plugin.common.EventChannel;

public class RecorderRecordStreamHandler implements EventChannel.StreamHandler {
  // Event producer
  private EventChannel.EventSink eventSink;

  @Override
  public void onListen(Object o, EventChannel.EventSink eventSink) {
    this.eventSink = eventSink;
  }

  @Override
  public void onCancel(Object o) {
    eventSink = null;
  }

  public void sendRecordChunkEvent(byte[] buffer) {
    if (eventSink != null) {
      eventSink.success(buffer);
    }
  }

  public void closeRecordChunkStream() {
    if (eventSink != null) {
      eventSink.endOfStream();
    }
  }
}
