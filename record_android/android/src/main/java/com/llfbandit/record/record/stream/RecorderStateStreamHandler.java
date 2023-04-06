package com.llfbandit.record.record.stream;

import android.app.Activity;

import androidx.annotation.Nullable;

import io.flutter.plugin.common.EventChannel;

public class RecorderStateStreamHandler implements EventChannel.StreamHandler {
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

  public void sendStateEvent(int state) {
    if (eventSink != null && activity != null) {
      activity.runOnUiThread(() -> eventSink.success(state));
    }
  }

  public void sendStateErrorEvent(Exception ex) {
    if (eventSink != null && activity != null) {
      activity.runOnUiThread(() -> eventSink.error("-1", ex.getMessage(), ex));
    }
  }

  public void setActivity(@Nullable Activity activity) {
    this.activity = activity;
  }
}
