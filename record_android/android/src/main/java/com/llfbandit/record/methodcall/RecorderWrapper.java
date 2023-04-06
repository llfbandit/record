package com.llfbandit.record.methodcall;

import android.app.Activity;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.llfbandit.record.record.AudioRecorder;
import com.llfbandit.record.record.RecordConfig;
import com.llfbandit.record.record.stream.RecorderRecordStreamHandler;
import com.llfbandit.record.record.stream.RecorderStateStreamHandler;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

class RecorderWrapper {
  static final String EVENTS_STATE_CHANNEL = "com.llfbandit.record/events";
  static final String EVENTS_RECORD_CHANNEL = "com.llfbandit.record/eventsRecord";

  private EventChannel eventChannel;
  private final RecorderStateStreamHandler recorderStateStreamHandler = new RecorderStateStreamHandler();
  private EventChannel eventRecordChannel;
  private final RecorderRecordStreamHandler recorderRecordStreamHandler = new RecorderRecordStreamHandler();

  @Nullable
  private AudioRecorder recorder;

  @Nullable
  private RecordConfig config;

  RecorderWrapper(@NonNull BinaryMessenger messenger) {
    eventChannel = new EventChannel(messenger, EVENTS_STATE_CHANNEL);
    eventChannel.setStreamHandler(recorderStateStreamHandler);

    eventRecordChannel = new EventChannel(messenger, EVENTS_RECORD_CHANNEL);
    eventRecordChannel.setStreamHandler(recorderRecordStreamHandler);
  }

  public void setActivity(@Nullable Activity activity) {
    recorderStateStreamHandler.setActivity(activity);
    recorderRecordStreamHandler.setActivity(activity);
  }

  void startRecordingToFile(RecordConfig config, @NonNull MethodChannel.Result result) {
    startRecording(config, result);
  }

  void startRecordingToStream(RecordConfig config, @NonNull MethodChannel.Result result) {
    startRecording(config, result);
  }

  void dispose() {
    if (recorder != null) {
      try {
        recorder.dispose();
      } catch (Exception ignored) {
      } finally {
        recorder = null;
      }
    }

    if (eventChannel != null) {
      eventChannel.setStreamHandler(null);
      eventChannel = null;
    }

    if (eventRecordChannel != null) {
      eventRecordChannel.setStreamHandler(null);
      eventRecordChannel = null;
    }
  }

  void pause(@NonNull MethodChannel.Result result) {
    if (recorder != null) {
      try {
        recorder.pause();
        result.success(null);
      } catch (Exception e) {
        result.error("-3", e.getMessage(), e.getCause());
      }
    } else {
      result.success(null);
    }
  }

  void isPaused(@NonNull MethodChannel.Result result) {
    if (recorder != null) {
      result.success(recorder.isPaused());
    } else {
      result.success(false);
    }
  }

  void isRecording(@NonNull MethodChannel.Result result) {
    if (recorder != null) {
      result.success(recorder.isRecording());
    } else {
      result.success(false);
    }
  }

  void getAmplitude(@NonNull MethodChannel.Result result) {
    if (recorder != null) {
      List<Double> amps = recorder.getAmplitude();

      Map<String, Object> amp = new HashMap<>();
      amp.put("current", amps.get(0));
      amp.put("max", amps.get(1));

      result.success(amp);
    } else {
      result.success(null);
    }
  }

  void resume(@NonNull MethodChannel.Result result) {
    if (recorder != null) {
      try {
        recorder.resume();
        result.success(null);
      } catch (Exception e) {
        result.error("-4", e.getMessage(), e.getCause());
      }
    } else {
      result.success(null);
    }
  }

  void stop(@NonNull MethodChannel.Result result) {
    if (recorder != null) {
      try {
        recorder.stop();
        result.success(config != null ? config.path : null);
      } catch (Exception e) {
        result.error("-2", e.getMessage(), e.getCause());
      }
    } else {
      result.success(null);
    }
  }

  private void startRecording(@NonNull RecordConfig config, @NonNull MethodChannel.Result result) {
    try {
      dispose();

      this.config = config;

      recorder = createRecorder(config);

      recorder.start();
      result.success(null);
    } catch (Exception e) {
      result.error("-1", e.getMessage(), e.getCause());
    }
  }

  private AudioRecorder createRecorder(@NonNull RecordConfig config) {
    return new AudioRecorder(
        config,
        recorderStateStreamHandler,
        recorderRecordStreamHandler
    );
  }
}
