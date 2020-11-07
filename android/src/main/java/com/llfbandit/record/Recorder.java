package com.llfbandit.record;

import androidx.annotation.NonNull;
import android.media.MediaRecorder;
import android.util.Log;

import io.flutter.plugin.common.MethodChannel.Result;

import java.lang.Exception;

class Recorder {
  private static final String LOG_TAG = "Record";

  private boolean isRecording = false;

  private MediaRecorder recorder = null;

  void start(@NonNull String path, int encoder, int bitRate, double samplingRate, @NonNull Result result) {
    stopRecording();

    Log.d(LOG_TAG, "Start recording");

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
        result.success(null);
    } catch (Exception e) {
        result.error("-1", "Start failed", e.getMessage());
    }
  }

  void stop(@NonNull Result result) {
    stopRecording();
    result.success(null);
  }

  void isRecording(@NonNull Result result) {
    result.success(isRecording);
  }

  void close() {
    stopRecording();
  }

  private void stopRecording() {
    if (recorder != null) {
      Log.d(LOG_TAG, "Stop recording");

      try {
        recorder.stop();
        recorder.reset();
        recorder.release();
      } catch (Exception e) {
        Log.d(LOG_TAG, "Stop failed");
      }
      recorder = null;
      isRecording = false;
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
    switch(encoder) {
    case 1:
      return MediaRecorder.AudioEncoder.AAC_ELD;
    case 2:
      return MediaRecorder.AudioEncoder.HE_AAC;
    case 3:
      return MediaRecorder.AudioEncoder.AMR_NB;
    case 4:
      return MediaRecorder.AudioEncoder.AMR_WB;
    case 5:
      return MediaRecorder.AudioEncoder.OPUS;
    default:
      return MediaRecorder.AudioEncoder.AAC;
    }
  }
}
