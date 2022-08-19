package com.llfbandit.record;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

/**
 * RecordPlugin
 */
public class RecordPlugin implements FlutterPlugin, ActivityAware {
  private static final String MESSAGES_CHANNEL = "com.llfbandit.record/messages";
  private static final String EVENTS_CHANNEL = "com.llfbandit.record/events";

  /// The MethodChannel that will the communication between Flutter and native Android
  private MethodChannel methodChannel;
  // Channel for communicating with flutter using async stream
  private EventChannel eventChannel;
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
    methodChannel = new MethodChannel(messenger, MESSAGES_CHANNEL);
    methodChannel.setMethodCallHandler(handler);

    binding.addRequestPermissionsResultListener(handler);

    eventChannel = new EventChannel(messenger, EVENTS_CHANNEL);
    eventChannel.setStreamHandler(handler);
  }

  private void stopPlugin() {
    activityBinding.removeRequestPermissionsResultListener(handler);
    activityBinding = null;
    methodChannel.setMethodCallHandler(null);
    eventChannel.setStreamHandler(null);
    handler.close();
    handler = null;
    methodChannel = null;
    eventChannel = null;
  }
  /// END ActivityAware
  /////////////////////////////////////////////////////////////////////////////
}
