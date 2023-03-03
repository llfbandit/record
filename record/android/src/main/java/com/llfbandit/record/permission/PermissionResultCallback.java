package com.llfbandit.record.permission;

@FunctionalInterface
public interface PermissionResultCallback {
  void onResult(boolean granted);
}