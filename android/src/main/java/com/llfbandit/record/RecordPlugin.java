package com.llfbandit.record;

import android.content.Context;
import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;

/** RecordPlugin */
public class RecordPlugin implements FlutterPlugin {
  // Supports the old pre-Flutter-1.12 Android projects.
  public static void registerWith(Registrar registrar) {
    final RecordPlugin plugin = new RecordPlugin();
    plugin.start(registrar.context(), registrar.messenger());
  }

  /// The MethodChannel that will the communication between Flutter and native Android
  private MethodChannel channel;
  /// Our call handler
  private MethodCallHandlerImpl handler;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    start(binding.getApplicationContext(), binding.getBinaryMessenger());
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    handler.close();
    channel.setMethodCallHandler(null);
  }

  private void start(Context applicationContext, BinaryMessenger messenger) {
    handler = new MethodCallHandlerImpl(applicationContext);
    channel = new MethodChannel(messenger, "com.llfbandit.record");
    channel.setMethodCallHandler(handler);
  }
}
