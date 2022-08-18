package com.llfbandit.record;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;

import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;

import java.io.File;
import java.io.IOException;
import java.util.Map;

import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry;

public class MethodCallHandlerImpl implements
    MethodCallHandler,
    EventChannel.StreamHandler,
    PluginRegistry.RequestPermissionsResultListener {

  private static final int RECORD_AUDIO_REQUEST_CODE = 1001;

  private static final int RECORD_STATE_PAUSE = 0;
  private static final int RECORD_STATE_RECORD = 1;
  private static final int RECORD_STATE_STOP = 2;

  private final Activity activity;
  private RecorderBase recorder;
  private Result pendingPermResult;
  // Event producer
  private EventChannel.EventSink eventSink;

  MethodCallHandlerImpl(Activity activity) {
    this.activity = activity;
  }

  void close() {
    if (recorder != null) {
      recorder.close();
    }
    pendingPermResult = null;
  }

  @Override
  @SuppressWarnings("ConstantConditions")
  public void onMethodCall(MethodCall call, @NonNull Result result) {
    switch (call.method) {
      case "start":
        String path = call.argument("path");

        if (path == null) {
          path = genTempFileName(result);
          if (path == null) return;
        }

        String encoder = call.argument("encoder");
        int bitRate = call.argument("bitRate");
        int samplingRate = call.argument("samplingRate");
        int numChannels = call.argument("numChannels");
        Map<String, Object> device = call.argument("device");

        recorder = selectRecorder(encoder);

        try {
          recorder.start(path, encoder, bitRate, samplingRate, numChannels, device);
          result.success(null);
          sendStateEvent(RECORD_STATE_RECORD);
        } catch (Exception e) {
          result.error("-1", e.getMessage(), e.getCause());
        }
        break;
      case "stop":
        if (recorder != null) {
          try {
            result.success(recorder.stop());
            sendStateEvent(RECORD_STATE_STOP);
          } catch (Exception e) {
            result.error("-2", e.getMessage(), e.getCause());
          }
        } else {
          result.success(null);
        }
        break;
      case "pause":
        if (recorder != null) {
          try {
            recorder.pause();
            result.success(null);
            sendStateEvent(RECORD_STATE_PAUSE);
          } catch (Exception e) {
            result.error("-3", e.getMessage(), e.getCause());
          }
        } else {
          result.success(null);
        }
        break;
      case "resume":
        if (recorder != null) {
          try {
            recorder.resume();
            result.success(null);
            sendStateEvent(RECORD_STATE_RECORD);
          } catch (Exception e) {
            result.error("-4", e.getMessage(), e.getCause());
          }
        } else {
          result.success(null);
        }
        break;
      case "isPaused":
        if (recorder != null) {
          result.success(recorder.isPaused());
        } else {
          result.success(false);
        }
        break;
      case "isRecording":
        if (recorder != null) {
          result.success(recorder.isRecording());
        } else {
          result.success(false);
        }
        break;
      case "hasPermission":
        hasPermission(result);
        break;
      case "getAmplitude":
        if (recorder != null) {
          result.success(recorder.getAmplitude());
        } else {
          result.success(null);
        }
        break;
      case "listInputDevices":
        result.success(null);
        break;
      case "dispose":
        close();
        result.success(null);
        break;
      case "isEncoderSupported":
        String codec = call.argument("encoder");
        RecorderBase rec = selectRecorder(codec);

        boolean isSupported = rec.isEncoderSupported(codec);
        result.success(isSupported);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  /////////////////////////////////////////////////////////////////////////////
  /// EventChannel.StreamHandler
  ///
  @Override
  public void onListen(Object o, EventChannel.EventSink eventSink) {
    this.eventSink = eventSink;
  }

  @Override
  public void onCancel(Object o) {
    eventSink = null;
  }
  ///
  /// END EventChannel.StreamHandler
  /////////////////////////////////////////////////////////////////////////////

  @Override
  public boolean onRequestPermissionsResult(
      int requestCode,
      @NonNull String[] permissions,
      @NonNull int[] grantResults
  ) {
    if (requestCode == RECORD_AUDIO_REQUEST_CODE) {
      if (pendingPermResult != null) {
        if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
          pendingPermResult.success(true);
        } else {
          pendingPermResult.success(false);
        }
        pendingPermResult = null;
        return true;
      }
    }

    return false;
  }

  private void hasPermission(@NonNull Result result) {
    if (!isPermissionGranted()) {
      pendingPermResult = result;
      askForPermission();
    } else {
      result.success(true);
    }
  }

  private boolean isPermissionGranted() {
    int result = ActivityCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO);
    return result == PackageManager.PERMISSION_GRANTED;
  }

  private void askForPermission() {
    ActivityCompat.requestPermissions(
        activity,
        new String[]{Manifest.permission.RECORD_AUDIO},
        MethodCallHandlerImpl.RECORD_AUDIO_REQUEST_CODE
    );
  }

  private RecorderBase selectRecorder(String encoder) {
    RecorderBase r = new AudioRecorder();
    if (r.isEncoderSupported(encoder)) {
      return r;
    }

    r = new MediaRecorder(activity);
    if (r.isEncoderSupported(encoder)) {
      return r;
    }

    return null;
  }

  private String genTempFileName(@NonNull Result result) {
    File outputDir = activity.getCacheDir();
    File outputFile;

    try {
      outputFile = File.createTempFile("audio", ".m4a", outputDir);
      return outputFile.getPath();
    } catch (IOException e) {
      result.error("record", "Cannot create temp file.", e.getMessage());
      e.printStackTrace();
    }

    return null;
  }

  private void sendStateEvent(int state) {
    if (eventSink != null) eventSink.success(state);
  }
}
