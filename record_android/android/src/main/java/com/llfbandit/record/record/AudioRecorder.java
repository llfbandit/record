package com.llfbandit.record.record;

import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.llfbandit.record.record.processor.AacProcessor;
import com.llfbandit.record.record.processor.AmrProcessor;
import com.llfbandit.record.record.processor.AudioProcessor;
import com.llfbandit.record.record.processor.FlacProcessor;
import com.llfbandit.record.record.processor.OggProcessor;
import com.llfbandit.record.record.processor.OpusProcessor;
import com.llfbandit.record.record.processor.PcmProcessor;
import com.llfbandit.record.record.processor.WavProcessor;
import com.llfbandit.record.record.stream.RecorderRecordStreamHandler;
import com.llfbandit.record.record.stream.RecorderStateStreamHandler;

import java.util.ArrayList;
import java.util.List;

public class AudioRecorder implements AudioProcessor.OnAudioProcessorListener {
  private static final String TAG = "AudioRecorder";

  // Recording config
  private final RecordConfig config;
  // Recorder streams
  private final RecorderStateStreamHandler recorderStateStreamHandler;
  private final RecorderRecordStreamHandler recorderRecordStreamHandler;

  @Nullable
  private AudioProcessor audioProcessor;

  private double amplitude = -160.0;
  // Max amplitude recorded
  private double maxAmplitude = -160.0;

  public AudioRecorder(
      @NonNull RecordConfig config,
      @NonNull RecorderStateStreamHandler recorderStateStreamHandler,
      @NonNull RecorderRecordStreamHandler recorderRecordStreamHandler
  ) {
    this.config = config;
    this.recorderStateStreamHandler = recorderStateStreamHandler;
    this.recorderRecordStreamHandler = recorderRecordStreamHandler;
  }

  public void dispose() {
    stop();
  }

  /**
   * Starts the recording with the given config.
   */
  public void start() throws Exception {
    audioProcessor = selectProcessor();

    audioProcessor.start(config);
  }

  /**
   * Stops the recording.
   */
  public void stop() {
    if (audioProcessor != null) {
      audioProcessor.stop();
    }
  }

  /**
   * Pauses the recording if currently running.
   */
  public void pause() {
    if (audioProcessor != null) {
      audioProcessor.pause();
    }
  }

  /**
   * Resumes the recording if currently paused.
   */
  public void resume() {
    if (audioProcessor != null) {
      audioProcessor.resume();
    }
  }

  /**
   * Gets the state the of recording
   *
   * @return True if recording. False otherwise.
   */
  public boolean isRecording() {
    if (audioProcessor != null) {
      return audioProcessor.isRecording();
    }

    return false;
  }

  /**
   * Gets the state the of recording
   *
   * @return True if paused. False otherwise.
   */
  public boolean isPaused() {
    if (audioProcessor != null) {
      return audioProcessor.isPaused();
    }

    return false;
  }

  /**
   * Gets the amplitude
   *
   * @return List with current and max amplitude values
   */
  public List<Double> getAmplitude() {
    List<Double> amps = new ArrayList<>();

    amps.add(amplitude);
    amps.add(maxAmplitude);

    return amps;
  }

  @Override
  public void onRecord() {
    updateState(RecordState.RECORD);
  }

  @Override
  public void onPause() {
    updateState(RecordState.PAUSE);
  }

  @Override
  public void onStop() {
    updateState(RecordState.STOP);
  }

  @Override
  public void onFailure(Exception ex) {
    Log.e(TAG, ex.getMessage(), ex);

    recorderStateStreamHandler.sendStateErrorEvent(ex);

    try {
      stop();
    } catch (Exception ignored) {
    }
  }

  @Override
  public void onAmplitude(int amplitude) {
    this.amplitude = amplitude;

    if (amplitude > maxAmplitude) {
      maxAmplitude = amplitude;
    }
  }

  @Override
  public void onAudioChunk(byte[] chunk) {
    recorderRecordStreamHandler.sendRecordChunkEvent(chunk);
  }

  private AudioProcessor selectProcessor() throws Exception {
    switch (config.encoder) {
      case "aacLc":
      case "aacEld":
      case "aacHe":
        return new AacProcessor(this);
      case "amrNb":
      case "amrWb":
        return new AmrProcessor(this);
      case "flac":
        return new FlacProcessor(this);
      case "pcm16bit":
      case "pcm8bit":
        return new PcmProcessor(this);
      case "opus":
        return new OpusProcessor(this);
      case "vorbisOgg":
        return new OggProcessor(this);
      case "wav":
        return new WavProcessor(this);
    }

    throw new Exception("Unknown encoder: " + config.encoder);
  }

  private void updateState(RecordState state) {
    recorderStateStreamHandler.sendStateEvent(state.id);
  }
}
