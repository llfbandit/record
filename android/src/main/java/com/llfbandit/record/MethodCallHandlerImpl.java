package com.llfbandit.record;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;

import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry;

public class MethodCallHandlerImpl implements MethodCallHandler, PluginRegistry.RequestPermissionsResultListener {
  private static final String LOG_TAG = "Record";
  private static final int RECORD_AUDIO_REQUEST_CODE = MethodCallHandlerImpl.class.hashCode() + 43;

  private final Activity activity;
  private Result pendingPermResult;
  private final Recorder recorder = new Recorder();

  MethodCallHandlerImpl(Activity activity) {
    this.activity = activity;
  }

  void close() {
    recorder.close();
  }

  @Override
  public void onMethodCall(MethodCall call, @NonNull Result result) {
    switch (call.method) {
      case "start":
        recorder.start(
          (String) call.argument("path"),
          (int) call.argument("encoder"),
          (int) call.argument("bitRate"),
          (double) call.argument("samplingRate"),
          result);
        break;
      case "stop":
        recorder.stop(result);
        break;
      case "isRecording":
        recorder.isRecording(result);
        break;
      case "hasPermission":
        hasPermission(result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  @Override
  public boolean onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
    if (requestCode == RECORD_AUDIO_REQUEST_CODE) {
      if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
        pendingPermResult.success(true);
      } else {
        pendingPermResult.error("-2", "Permission denied", null);          
      }
      pendingPermResult = null;
      return true;
    }

    return false;
  }

  private void hasPermission(@NonNull Result result) {
    if (!isPermissionGranted(Manifest.permission.RECORD_AUDIO)) {
      pendingPermResult = result;
      askForPermission(Manifest.permission.RECORD_AUDIO, RECORD_AUDIO_REQUEST_CODE);
      return;
    } else {
      result.success(true);
    }
  }

  private boolean isPermissionGranted(String permissionName) {
    int result = ActivityCompat.checkSelfPermission(activity, permissionName);
    return result == PackageManager.PERMISSION_GRANTED;
  }

  private void askForPermission(String permissionName, int requestCode) {
    ActivityCompat.requestPermissions(activity, new String[]{permissionName}, requestCode);
  }
}