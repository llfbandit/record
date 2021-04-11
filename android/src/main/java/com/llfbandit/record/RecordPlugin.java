package com.llfbandit.record;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;

import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry;

/**
 * RecordPlugin
 */
public class RecordPlugin implements FlutterPlugin, ActivityAware, PluginRegistry.RequestPermissionsResultListener, MethodCallHandler {
    private static final int RECORD_AUDIO_REQUEST_CODE = RecordPlugin.class.hashCode() + 43;
    private MethodChannel channel;

    private Context applicationContext;
    private Recorder recorder;

    private ActivityPluginBinding activityPluginBinding;
    private Result pendingPermResult;

    /// --- FlutterPlugin
    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), "com.llfbandit.record");
        channel.setMethodCallHandler(this);

        applicationContext = binding.getApplicationContext();
        recorder = new Recorder();
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        channel = null;

        applicationContext = null;
        recorder.close();
        recorder = null;
    }

    // --- ActivityAware

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activityPluginBinding = binding;
        activityPluginBinding.addRequestPermissionsResultListener(this);
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
        activityPluginBinding.removeRequestPermissionsResultListener(this);
        activityPluginBinding = null;
    }

    // --- RequestPermissionsResultListener

    @Override
    public boolean onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
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

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
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
            default:
                result.notImplemented();
                break;
        }
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
        int result = ActivityCompat.checkSelfPermission(activityPluginBinding.getActivity(), Manifest.permission.RECORD_AUDIO);
        return result == PackageManager.PERMISSION_GRANTED;
    }

    private void askForPermission() {
        ActivityCompat.requestPermissions(
                activityPluginBinding.getActivity(),
                new String[]{Manifest.permission.RECORD_AUDIO},
                RECORD_AUDIO_REQUEST_CODE
        );
    }
}
