package com.llfbandit.record;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.media.MediaRecorder;
import android.os.Environment;
import android.util.Log;
import androidx.annotation.NonNull;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.io.IOException;
import java.util.Calendar;
import java.util.Date;
import java.util.HashMap;

public class MethodCallHandlerImpl implements MethodCallHandler {
  private static final String LOG_TAG = "Record";
  private Recorder recorder = new Recorder();

  private final Context context;

  MethodCallHandlerImpl(Context context) {
    this.context = context;
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
          (int) call.argument("outputFormat"),
          (int) call.argument("encoder"),
          (int) call.argument("bitRate"),
          (float) call.argument("samplingRate"),
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

  private void hasPermission(@NonNull Result result) {
    final PackageManager pm = context.getPackageManager();
    final String pkgName = context.getPackageName();

    int perm = pm.checkPermission(Manifest.permission.RECORD_AUDIO, pkgName);
    boolean permGranted = perm == PackageManager.PERMISSION_GRANTED;

    if (permGranted) {
      result.success(true);
    } else {
      result.error("-2", "Permission denied", null);
    }    
  }
}