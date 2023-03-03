package com.llfbandit.record.stream;

import io.flutter.plugin.common.EventChannel;

public class RecorderStateStreamHandler implements EventChannel.StreamHandler {
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

  public void sendStateEvent(int state) {
    if (eventSink != null) {
      eventSink.success(state);
    }
  }
}
