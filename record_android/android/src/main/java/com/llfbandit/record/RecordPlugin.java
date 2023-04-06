package com.llfbandit.record;

import androidx.annotation.NonNull;

import com.llfbandit.record.methodcall.MethodCallHandlerImpl;
import com.llfbandit.record.permission.PermissionManager;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;

/**
 * RecordPlugin
 */
public class RecordPlugin implements FlutterPlugin, ActivityAware {
  static final String MESSAGES_CHANNEL = "com.llfbandit.record/messages";

  /// The MethodChannel that will the communication between Flutter and native Android
  private MethodChannel methodChannel;
  /// Our call handler
  private MethodCallHandlerImpl callHandler;

  private PermissionManager permissionManager;
  private ActivityPluginBinding activityBinding;

  /////////////////////////////////////////////////////////////////////////////
  /// FlutterPlugin
  /////////////////////////////////////////////////////////////////////////////
  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    startPlugin(binding.getBinaryMessenger());
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    stopPlugin();
  }
  /// END FlutterPlugin
  /////////////////////////////////////////////////////////////////////////////


  /////////////////////////////////////////////////////////////////////////////
  /// ActivityAware
  /////////////////////////////////////////////////////////////////////////////
  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
    activityBinding = binding;

    permissionManager.setActivity(activityBinding.getActivity());
    activityBinding.addRequestPermissionsResultListener(permissionManager);

    callHandler.setActivity(activityBinding.getActivity());
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    onDetachedFromActivity();
  }

  @Override
  public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
    onDetachedFromActivity();
    onAttachedToActivity(binding);
  }

  @Override
  public void onDetachedFromActivity() {
    permissionManager.setActivity(null);
    activityBinding.removeRequestPermissionsResultListener(permissionManager);

    callHandler.setActivity(null);

    activityBinding = null;
  }
  /// END ActivityAware
  /////////////////////////////////////////////////////////////////////////////

  private void startPlugin(BinaryMessenger messenger) {
    permissionManager = new PermissionManager();

    callHandler = new MethodCallHandlerImpl(permissionManager, messenger);

    methodChannel = new MethodChannel(messenger, MESSAGES_CHANNEL);
    methodChannel.setMethodCallHandler(callHandler);
  }

  private void stopPlugin() {
    methodChannel.setMethodCallHandler(null);
    methodChannel = null;
    callHandler.dispose();
    callHandler = null;
  }
}
