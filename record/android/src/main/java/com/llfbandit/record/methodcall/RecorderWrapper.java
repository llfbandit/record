package com.llfbandit.record.methodcall;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.llfbandit.record.record.AudioRecorder;
import com.llfbandit.record.record.RecordConfig;
import com.llfbandit.record.record.RecorderBase;
import com.llfbandit.record.stream.RecorderRecordStreamHandler;
import com.llfbandit.record.stream.RecorderStateStreamHandler;

import io.flutter.plugin.common.MethodChannel;

class RecorderWrapper {
  @Nullable
  private RecorderBase recorder;

  // Event producer
  private final RecorderStateStreamHandler recorderStateStreamHandler;
  private final RecorderRecordStreamHandler recorderRecordStreamHandler;

  RecorderWrapper(
      @NonNull RecorderStateStreamHandler recorderStateStreamHandler,
      @NonNull RecorderRecordStreamHandler recorderRecordStreamHandler
  ) {
    this.recorderStateStreamHandler = recorderStateStreamHandler;
    this.recorderRecordStreamHandler = recorderRecordStreamHandler;
  }

  void startRecordingToFile(RecordConfig config, @NonNull MethodChannel.Result result) {
    startRecording(config, result);
  }

  void startRecordingToStream(RecordConfig config, @NonNull MethodChannel.Result result) {
    startRecording(config, result);
  }

  void close() {
    if (recorder != null) {
      recorder.close();
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
      result.success(recorder.getAmplitude());
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
        result.success(recorder.stop());
      } catch (Exception e) {
        result.error("-2", e.getMessage(), e.getCause());
      }
    } else {
      result.success(null);
    }
  }

  private void startRecording(@NonNull RecordConfig config, @NonNull MethodChannel.Result result) {
    try {
      close();
      recorder = null;

      recorder = createRecorder(config);

      recorder.start();
      result.success(null);
    } catch (Exception e) {
      result.error("-1", e.getMessage(), e.getCause());
    }
  }

  private RecorderBase createRecorder(@NonNull RecordConfig config) throws Exception {
    return new AudioRecorder(
        config,
        recorderStateStreamHandler,
        recorderRecordStreamHandler
    );
  }
}
