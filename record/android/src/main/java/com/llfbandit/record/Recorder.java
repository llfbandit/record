package com.llfbandit.record;

import android.media.MediaRecorder;
import android.os.Build;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.RequiresApi;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.plugin.common.MethodChannel.Result;

class Recorder {
  private static final String LOG_TAG = "Record";

  private boolean isRecording = false;
  private boolean isPaused = false;

  private MediaRecorder recorder = null;
  private String path;
  private Double maxAmplitude = -160.0;

  void start(
          @NonNull String path,
          int encoder,
          int bitRate,
          double samplingRate,
          @NonNull Result result
  ) {
    stopRecording();

    Log.d(LOG_TAG, "Start recording");

    this.path = path;

    recorder = new MediaRecorder();
    recorder.setAudioSource(MediaRecorder.AudioSource.MIC);
    recorder.setAudioEncodingBitRate(bitRate);
    recorder.setAudioSamplingRate((int) samplingRate);
    recorder.setOutputFormat(getOutputFormat(encoder));
    // must be set after output format
    recorder.setAudioEncoder(getEncoder(encoder));
    recorder.setOutputFile(path);

    try {
      recorder.prepare();
      recorder.start();
      isRecording = true;
      isPaused = false;
      result.success(null);
    } catch (Exception e) {
      recorder.release();
      recorder = null;
      result.error("-1", "Start recording failure", e.getMessage());
    }
  }

  void stop(@NonNull Result result) {
    stopRecording();
    result.success(path);
  }

  @RequiresApi(api = Build.VERSION_CODES.N)
  void pause(@NonNull Result result) {
    pauseRecording();
    result.success(null);
  }

  @RequiresApi(api = Build.VERSION_CODES.N)
  void resume(@NonNull Result result) {
    resumeRecording();
    result.success(null);
  }

  void isRecording(@NonNull Result result) {
    result.success(isRecording);
  }

  void isPaused(@NonNull Result result) {
    result.success(isPaused);
  }

  void getAmplitude(@NonNull Result result) {
    Map<String, Object> amp = new HashMap<>();

    Double current = -160.0;

    if (isRecording) {
      current = 20 * Math.log10(recorder.getMaxAmplitude() / 32768.0);

      if (current > maxAmplitude) {
        maxAmplitude = current;
      }
    }

    amp.put("current", current);
    amp.put("max", maxAmplitude);

    result.success(amp);
  }

  void close() {
    stopRecording();
  }

  private void stopRecording() {
    if (recorder != null) {
      try {
        if (isRecording || isPaused) {
          Log.d(LOG_TAG, "Stop recording");
          recorder.stop();
        }
      } catch (IllegalStateException ex) {
        // Mute this exception since 'isRecording' can't be 100% sure
      } finally {
        recorder.reset();
        recorder.release();
        recorder = null;
      }
    }

    isRecording = false;
    isPaused = false;
    maxAmplitude = -160.0;
  }

  @RequiresApi(api = Build.VERSION_CODES.N)
  private void pauseRecording() {
    if (recorder != null) {
      try {
        if (isRecording) {
          Log.d(LOG_TAG, "Pause recording");
          recorder.pause();
          isPaused = true;
        }
      } catch (IllegalStateException ex) {
        Log.d(LOG_TAG, "Did you call pause() before before start() or after stop()?\n" + ex.getMessage());
      }
    }
  }

  @RequiresApi(api = Build.VERSION_CODES.N)
  private void resumeRecording() {
    if (recorder != null) {
      try {
        if (isPaused) {
          Log.d(LOG_TAG, "Resume recording");
          recorder.resume();
          isPaused = false;
        }
      } catch (IllegalStateException ex) {
        Log.d(LOG_TAG, "Did you call resume() before before start() or after stop()?\n" + ex.getMessage());
      }
    }
  }

  private int getOutputFormat(int encoder) {
    if (encoder == 3 || encoder == 4) {
      return MediaRecorder.OutputFormat.THREE_GPP;
    }

    return MediaRecorder.OutputFormat.MPEG_4;
  }

  // https://developer.android.com/reference/android/media/MediaRecorder.AudioEncoder
  private int getEncoder(int encoder) {
    switch (encoder) {
      case 1:
        return MediaRecorder.AudioEncoder.AAC_ELD;
      case 2:
        return MediaRecorder.AudioEncoder.HE_AAC;
      case 3:
        return MediaRecorder.AudioEncoder.AMR_NB;
      case 4:
        return MediaRecorder.AudioEncoder.AMR_WB;
      case 5:
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
          return MediaRecorder.AudioEncoder.OPUS;
        } else {
          Log.d(LOG_TAG, "OPUS codec is available starting from API 29.\nFalling back to AAC");
        }
      default:
        return MediaRecorder.AudioEncoder.AAC;
    }
  }
}
