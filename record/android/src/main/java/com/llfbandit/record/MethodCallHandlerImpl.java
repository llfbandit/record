package com.llfbandit.record;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.os.Build;

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
  private final Recorder recorder = new Recorder();
  private Result pendingPermResult;

  MethodCallHandlerImpl(Activity activity) {
    this.activity = activity;
  }

  void close() {
    recorder.close();
    pendingPermResult = null;
  }

  @Override
  public void onMethodCall(MethodCall call, @NonNull Result result) {
    switch (call.method) {
      case "start":
        String path = (String) call.argument("path");

        if (path == null) {
          File outputDir = activity.getCacheDir();
          File outputFile = null;
          try {
            outputFile = File.createTempFile("audio", ".m4a", outputDir);
            path = outputFile.getPath();
          } catch (IOException e) {
            e.printStackTrace();
          }
        }

        recorder.start(
                path,
                (int) call.argument("encoder"),
                (int) call.argument("bitRate"),
                (double) call.argument("samplingRate"),
                result);
        break;
      case "stop":
        recorder.stop(result);
        break;
      case "pause":
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
          recorder.pause(result);
        }
        break;
      case "resume":
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
          recorder.resume(result);
        }
        break;
      case "isPaused":
        recorder.isPaused(result);
        break;
      case "isRecording":
        recorder.isRecording(result);
        break;
      case "hasPermission":
        hasPermission(result);
        break;
      case "getAmplitude":
        recorder.getAmplitude(result);
        break;
      case "dispose":
        close();
        result.success(null);
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
}