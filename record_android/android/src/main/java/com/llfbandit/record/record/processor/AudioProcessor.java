package com.llfbandit.record.record.processor;

import com.llfbandit.record.record.RecordConfig;

public interface AudioProcessor {
  interface OnAudioProcessorListener {
    void onRecord();

    void onPause();

    void onStop();

    void onFailure(Exception ex);

    void onAmplitude(int amplitude);

    void onAudioChunk(byte[] chunk);
  }

  void start(RecordConfig config) throws Exception;

  boolean isRecording();

  void stop();

  void pause();

  boolean isPaused();

  void resume();
}