package com.llfbandit.record.record.stream;

import android.app.Activity;

import androidx.annotation.Nullable;

import io.flutter.plugin.common.EventChannel;

public class RecorderRecordStreamHandler implements EventChannel.StreamHandler {
  // Event producer
  private EventChannel.EventSink eventSink;

  @Nullable
  private Activity activity;

  @Override
  public void onListen(Object o, EventChannel.EventSink eventSink) {
    this.eventSink = eventSink;
  }

  @Override
  public void onCancel(Object o) {
    eventSink = null;
  }

  public void sendRecordChunkEvent(byte[] buffer) {
    if (eventSink != null && activity != null) {
      activity.runOnUiThread(() -> eventSink.success(buffer));
    }
  }

  public void setActivity(@Nullable Activity activity) {
    this.activity = activity;
  }
}
