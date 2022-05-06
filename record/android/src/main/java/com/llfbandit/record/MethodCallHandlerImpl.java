package com.llfbandit.record;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;

import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;

import java.io.File;
import java.io.IOException;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry;

public class MethodCallHandlerImpl
        implements MethodCallHandler, PluginRegistry.RequestPermissionsResultListener {

  private static final int RECORD_AUDIO_REQUEST_CODE = 1001;

  private final Activity activity;
  private RecorderBase recorder;
  private Result pendingPermResult;

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

        recorder = selectRecorder(encoder);

        recorder.start(path, encoder, bitRate, samplingRate, result);
        break;
      case "stop":
        if (recorder != null) {
          recorder.stop(result);
        } else {
          result.success(null);
        }
        break;
      case "pause":
        if (recorder != null) {
          recorder.pause(result);
        } else {
          result.success(null);
        }
        break;
      case "resume":
        if (recorder != null) {
          recorder.resume(result);
        } else {
          result.success(null);
        }
        break;
      case "isPaused":
        if (recorder != null) {
          recorder.isPaused(result);
        } else {
          result.success(false);
        }
        break;
      case "isRecording":
        if (recorder != null) {
          recorder.isRecording(result);
        } else {
          result.success(false);
        }
        break;
      case "hasPermission":
        hasPermission(result);
        break;
      case "getAmplitude":
        if (recorder != null) {
          recorder.getAmplitude(result);
        } else {
          result.success(null);
        }
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

  @Override
  public boolean onRequestPermissionsResult(
          int requestCode,
          String[] permissions,
          int[] grantResults
  ) {
    if (requestCode == RECORD_AUDIO_REQUEST_CODE) {
      if (pendingPermResult != null) {
        if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
          pendingPermResult.success(true);
        } else {
          pendingPermResult.error("-2", "Permission denied", null);
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

    r = new MediaRecorder();
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
}
