package com.llfbandit.record;

import androidx.annotation.NonNull;

import com.llfbandit.record.methodcall.MethodCallHandlerImpl;
import com.llfbandit.record.permission.PermissionManager;
import com.llfbandit.record.stream.RecorderRecordStreamHandler;
import com.llfbandit.record.stream.RecorderStateStreamHandler;

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
  static final String MESSAGES_CHANNEL = "com.llfbandit.record/messages";
  static final String EVENTS_STATE_CHANNEL = "com.llfbandit.record/events";
  static final String EVENTS_RECORD_CHANNEL = "com.llfbandit.record/eventsRecord";

  /// The MethodChannel that will the communication between Flutter and native Android
  private MethodChannel methodChannel;
  // Channel for communicating with flutter using async stream
  private EventChannel eventChannel;
  private RecorderStateStreamHandler recorderStateStreamHandler;
  // Channel for communicating with flutter using async stream
  private EventChannel eventRecordChannel;
  private RecorderRecordStreamHandler recorderRecordStreamHandler;
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
    permissionManager.setActivity(null);
    activityBinding.removeRequestPermissionsResultListener(permissionManager);

    activityBinding = null;
  }
  /// END ActivityAware
  /////////////////////////////////////////////////////////////////////////////

  private void startPlugin(BinaryMessenger messenger) {
    recorderStateStreamHandler = new RecorderStateStreamHandler();
    recorderRecordStreamHandler = new RecorderRecordStreamHandler();

    permissionManager = new PermissionManager();

    callHandler = new MethodCallHandlerImpl(
        permissionManager,
        recorderStateStreamHandler,
        recorderRecordStreamHandler
    );

    methodChannel = new MethodChannel(messenger, MESSAGES_CHANNEL);
    methodChannel.setMethodCallHandler(callHandler);

    eventChannel = new EventChannel(messenger, EVENTS_STATE_CHANNEL);
    eventChannel.setStreamHandler(recorderStateStreamHandler);

    eventRecordChannel = new EventChannel(messenger, EVENTS_RECORD_CHANNEL);
    eventRecordChannel.setStreamHandler(recorderRecordStreamHandler);
  }

  private void stopPlugin() {
    methodChannel.setMethodCallHandler(null);
    methodChannel = null;
    callHandler.close();
    callHandler = null;

    eventChannel.setStreamHandler(null);
    eventChannel = null;
    recorderStateStreamHandler = null;

    eventRecordChannel.setStreamHandler(null);
    eventRecordChannel = null;
    recorderRecordStreamHandler = null;
  }
}
