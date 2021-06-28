package com.llfbandit.record;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;

/**
 * RecordPlugin
 */
public class RecordPlugin implements FlutterPlugin, ActivityAware {
  /// The MethodChannel that will the communication between Flutter and native Android
  private MethodChannel channel;
  /// Our call handler
  private MethodCallHandlerImpl handler;
  private FlutterPluginBinding pluginBinding;
  private ActivityPluginBinding activityBinding;

  /////////////////////////////////////////////////////////////////////////////
  /// FlutterPlugin
  /////////////////////////////////////////////////////////////////////////////
  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    pluginBinding = binding;
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    pluginBinding = null;
  }
  /// END FlutterPlugin
  /////////////////////////////////////////////////////////////////////////////


  /////////////////////////////////////////////////////////////////////////////
  /// ActivityAware
  /////////////////////////////////////////////////////////////////////////////
  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
    activityBinding = binding;

    startPlugin(pluginBinding.getBinaryMessenger(), binding);
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    onDetachedFromActivity();
  }

  @Override
  public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
    onAttachedToActivity(binding);
  }

  @Override
  public void onDetachedFromActivity() {
    stopPlugin();
  }

  private void startPlugin(BinaryMessenger messenger, ActivityPluginBinding binding) {

    handler = new MethodCallHandlerImpl(binding.getActivity());
    channel = new MethodChannel(messenger, "com.llfbandit.record");
    channel.setMethodCallHandler(handler);

    binding.addRequestPermissionsResultListener(handler);
  }

  private void stopPlugin() {
    activityBinding.removeRequestPermissionsResultListener(handler);
    activityBinding = null;
    channel.setMethodCallHandler(null);
    handler.close();
    handler = null;
    channel = null;
  }
  /// END ActivityAware
  /////////////////////////////////////////////////////////////////////////////
}
