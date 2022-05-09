package com.llfbandit.record;

import android.os.Build;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.RequiresApi;

import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.MethodChannel.Result;

class MediaRecorder implements RecorderBase {
  private static final String LOG_TAG = "Record - MR";

  private boolean isRecording = false;
  private boolean isPaused = false;

  private android.media.MediaRecorder recorder = null;
  private String path;
  private Double maxAmplitude = -160.0;

  @Override
  public void start(
          @NonNull String path,
          String encoder,
          int bitRate,
          int samplingRate,
          @NonNull Result result
  ) {
    stopRecording();

    Log.d(LOG_TAG, "Start recording");

    this.path = path;

    recorder = new android.media.MediaRecorder();
    recorder.setAudioSource(android.media.MediaRecorder.AudioSource.DEFAULT);
    recorder.setAudioEncodingBitRate(bitRate);
    recorder.setAudioSamplingRate(samplingRate);
    recorder.setOutputFormat(getOutputFormat(encoder));

    // must be set after output format
    Integer format = getEncoder(encoder);
    if (format == null) {
      Log.d(LOG_TAG, "Falling back to AAC LC");
      format = android.media.MediaRecorder.AudioEncoder.AAC;
    }

    recorder.setAudioEncoder(format);
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

  @Override
  public void stop(@NonNull Result result) {
    stopRecording();
    result.success(path);
  }

  @Override
  @RequiresApi(api = Build.VERSION_CODES.N)
  public void pause(@NonNull Result result) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      pauseRecording();
    }
    result.success(null);
  }

  @Override
  @RequiresApi(api = Build.VERSION_CODES.N)
  public void resume(@NonNull Result result) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      resumeRecording();
    }
    result.success(null);
  }

  @Override
  public void isRecording(@NonNull Result result) {
    result.success(isRecording);
  }

  @Override
  public void isPaused(@NonNull Result result) {
    result.success(isPaused);
  }

  @Override
  public void getAmplitude(@NonNull Result result) {
    Map<String, Object> amp = new HashMap<>();

    double current = -160.0;

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

  @Override
  public boolean isEncoderSupported(String encoder) {
    Integer format = getEncoder(encoder);
    return format != null;
  }

  @Override
  public void close() {
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

  private int getOutputFormat(String encoder) {
    switch (encoder) {
      case "aacLc":
      case "aacEld":
      case "aacHe":
        return android.media.MediaRecorder.OutputFormat.MPEG_4;
      case "amrNb":
      case "amrWb":
        return android.media.MediaRecorder.OutputFormat.THREE_GPP;
      case "opus":
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
          return android.media.MediaRecorder.OutputFormat.OGG;
        }
      case "vorbisOgg":
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
          return android.media.MediaRecorder.OutputFormat.OGG;
        }
        return android.media.MediaRecorder.OutputFormat.MPEG_4;
    }

    return android.media.MediaRecorder.OutputFormat.DEFAULT;
  }

  // https://developer.android.com/reference/android/media/MediaRecorder.AudioEncoder
  private Integer getEncoder(String encoder) {
    switch (encoder) {
      case "aacLc":
        return android.media.MediaRecorder.AudioEncoder.AAC;
      case "aacEld":
        return android.media.MediaRecorder.AudioEncoder.AAC_ELD;
      case "aacHe":
        return android.media.MediaRecorder.AudioEncoder.HE_AAC;
      case "amrNb":
        return android.media.MediaRecorder.AudioEncoder.AMR_NB;
      case "amrWb":
        return android.media.MediaRecorder.AudioEncoder.AMR_WB;
      case "opus":
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
          return android.media.MediaRecorder.AudioEncoder.OPUS;
        }
      case "vorbisOgg":
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
          return android.media.MediaRecorder.AudioEncoder.VORBIS;
        }
    }

    return null;
  }
}
