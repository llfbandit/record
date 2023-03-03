package com.llfbandit.record.permission;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.app.ActivityCompat;

import io.flutter.plugin.common.PluginRegistry;

final public class PermissionManager implements PluginRegistry.RequestPermissionsResultListener {
  private static final int RECORD_AUDIO_REQUEST_CODE = 1001;

  @Nullable
  private PermissionResultCallback resultCallback;

  @Nullable
  private Activity activity;

  public void setActivity(@Nullable Activity activity) {
    this.activity = activity;
  }

  @Override
  public boolean onRequestPermissionsResult(
      int requestCode,
      @NonNull String[] permissions,
      @NonNull int[] grantResults
  ) {
    if (requestCode == RECORD_AUDIO_REQUEST_CODE && resultCallback != null) {
      boolean granted = grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED;
      resultCallback.onResult(granted);
      resultCallback = null;
      return true;
    }

    return false;
  }

  public void hasPermission(@NonNull PermissionResultCallback resultCallback) {
    if (activity == null) {
      resultCallback.onResult(false);
      return;
    }

    if (!isPermissionGranted(activity)) {
      this.resultCallback = resultCallback;

      ActivityCompat.requestPermissions(
          activity,
          new String[]{Manifest.permission.RECORD_AUDIO},
          RECORD_AUDIO_REQUEST_CODE
      );
    } else {
      resultCallback.onResult(true);
    }
  }

  private boolean isPermissionGranted(@NonNull Activity activity) {
    int result = ActivityCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO);
    return result == PackageManager.PERMISSION_GRANTED;
  }
}
