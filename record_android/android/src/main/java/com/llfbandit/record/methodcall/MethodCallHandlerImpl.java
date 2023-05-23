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
import java.util.concurrent.ConcurrentHashMap;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

public class MethodCallHandlerImpl implements MethodCallHandler {
  private final PermissionManager permissionManager;
  private final BinaryMessenger messenger;
  @Nullable
  private Activity activity;

  private final ConcurrentHashMap<String, RecorderWrapper> recorders = new ConcurrentHashMap<>();

  public MethodCallHandlerImpl(
      @NonNull PermissionManager permissionManager,
      @NonNull BinaryMessenger messenger) {

    this.permissionManager = permissionManager;
    this.messenger = messenger;
  }

  public void dispose() {
    for (RecorderWrapper recorder : recorders.values()) {
      recorder.dispose();
    }
    recorders.clear();
  }

  public void setActivity(@Nullable Activity activity) {
    this.activity = activity;

    for (RecorderWrapper recorder : recorders.values()) {
      recorder.setActivity(activity);
    }
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    String recorderId = call.argument("recorderId");
    if (recorderId == null || recorderId.isEmpty()) {
      result.error("record", "Call missing mandatory parameter recorderId.", null);
      return;
    }

    if (call.method.equals("create")) {
      try {
        createRecorder(recorderId);
        result.success(null);
      } catch (Exception e) {
        result.error("record", "Cannot create recording configuration.", e.getMessage());
      }
      return;
    }

    RecorderWrapper recorder = recorders.get(recorderId);
    if (recorder == null) {
      result.error(
          "record",
          "Recorder has not yet been created or has already been disposed.", null
      );
      return;
    }

    switch (call.method) {
      case "start":
        try {
          RecordConfig config = getRecordConfig(call);
          recorder.startRecordingToFile(config, result);
        } catch (IOException e) {
          result.error("record", "Cannot create recording configuration.", e.getMessage());
        }
        break;
      case "startStream":
        try {
          RecordConfig config = getRecordConfig(call);
          recorder.startRecordingToStream(config, result);
        } catch (IOException e) {
          result.error("record", "Cannot create recording configuration.", e.getMessage());
        }
        break;
      case "stop":
        recorder.stop(result);
        break;
      case "pause":
        recorder.pause(result);
        break;
      case "resume":
        recorder.resume(result);
        break;
      case "isPaused":
        recorder.isPaused(result);
        break;
      case "isRecording":
        recorder.isRecording(result);
        break;
      case "hasPermission":
        permissionManager.hasPermission(result::success);
        break;
      case "getAmplitude":
        recorder.getAmplitude(result);
        break;
      case "listInputDevices":
        result.success(null);
        break;
      case "dispose":
        recorder.dispose();
        recorders.remove(recorderId);
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

  private void createRecorder(String recorderId) {
    RecorderWrapper recorder = new RecorderWrapper(recorderId, messenger);
    recorder.setActivity(activity);
    recorders.put(recorderId, recorder);
  }

  private RecordConfig getRecordConfig(@NonNull MethodCall call) throws IOException {
    return new RecordConfig(
        call.argument("path"),
        Utils.firstNonNull(call.argument("encoder"), "aacLc"),
        Utils.firstNonNull(call.argument("bitRate"), 128000),
        Utils.firstNonNull(call.argument("samplingRate"), 44100),
        Utils.firstNonNull(call.argument("numChannels"), 2),
        call.argument("device"),
        Utils.firstNonNull(call.argument("autoGain"), false),
        Utils.firstNonNull(call.argument("echoCancel"), false),
        Utils.firstNonNull(call.argument("noiseCancel"), false)
    );
  }
}
