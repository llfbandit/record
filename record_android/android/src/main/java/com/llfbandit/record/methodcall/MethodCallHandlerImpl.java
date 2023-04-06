package com.llfbandit.record.methodcall;

import android.app.Activity;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.llfbandit.record.Utils;
import com.llfbandit.record.permission.PermissionManager;
import com.llfbandit.record.record.RecordConfig;
import com.llfbandit.record.record.format.AudioFormats;

import java.io.IOException;
import java.util.Objects;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

public class MethodCallHandlerImpl implements MethodCallHandler {
  private final PermissionManager permissionManager;
  private final RecorderWrapper recorderWrapper;

  public MethodCallHandlerImpl(
      @NonNull PermissionManager permissionManager,
      @NonNull BinaryMessenger messenger) {

    this.permissionManager = permissionManager;

    recorderWrapper = new RecorderWrapper(messenger);
  }

  public void dispose() {
    recorderWrapper.dispose();
  }

  public void setActivity(@Nullable Activity activity) {
    recorderWrapper.setActivity(activity);
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    switch (call.method) {
      case "start":
        try {
          RecordConfig config = getRecordConfig(call);
          recorderWrapper.startRecordingToFile(config, result);
        } catch (IOException e) {
          result.error("record", "Cannot create recording configuration.", e.getMessage());
        }
        break;
      case "startStream":
        try {
          RecordConfig config = getRecordConfig(call);
          recorderWrapper.startRecordingToStream(config, result);
        } catch (IOException e) {
          result.error("record", "Cannot create recording configuration.", e.getMessage());
        }
        break;
      case "stop":
        recorderWrapper.stop(result);
        break;
      case "pause":
        recorderWrapper.pause(result);
        break;
      case "resume":
        recorderWrapper.resume(result);
        break;
      case "isPaused":
        recorderWrapper.isPaused(result);
        break;
      case "isRecording":
        recorderWrapper.isRecording(result);
        break;
      case "hasPermission":
        permissionManager.hasPermission(result::success);
        break;
      case "getAmplitude":
        recorderWrapper.getAmplitude(result);
        break;
      case "listInputDevices":
        result.success(null);
        break;
      case "dispose":
        recorderWrapper.dispose();
        result.success(null);
        break;
      case "isEncoderSupported":
        String codec = call.argument("encoder");
        boolean isSupported = AudioFormats.isEncoderSupported(
            AudioFormats.getMimeType(Objects.requireNonNull(codec))
        );
        result.success(isSupported);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private RecordConfig getRecordConfig(@NonNull MethodCall call) throws IOException {
    return new RecordConfig(
        call.argument("path"),
        Utils.firstNonNull(call.argument("encoder"), "aacLc"),
        Utils.firstNonNull(call.argument("bitRate"), 128000),
        Utils.firstNonNull(call.argument("samplingRate"), 44100),
        Utils.firstNonNull(call.argument("numChannels"), 2),
        call.argument("device"),
        Utils.firstNonNull(call.argument("noiseCancel"), false),
        Utils.firstNonNull(call.argument("autoGain"), false)
    );
  }
}
