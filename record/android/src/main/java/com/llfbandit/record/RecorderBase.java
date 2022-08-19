package com.llfbandit.record;

import androidx.annotation.NonNull;

import java.util.Map;

public interface RecorderBase {
  /**
   * Starts the recording with the given parameters.
   *
   * @param path         The output path to write the file. Must be valid.
   * @param encoder      The encoder enum index from dart side.
   * @param bitRate      The bit rate of encoded file.
   * @param samplingRate The sampling rate of encoded file.
   * @param numChannels  The number of channels.
   * @param device       The input device to acquire audio data.
   */
  void start(
      @NonNull String path,
      String encoder,
      int bitRate,
      int samplingRate,
      int numChannels,
      Map<String, Object> device) throws Exception;

  /**
   * Stops the recording.
   */
  String stop();

  /**
   * Pauses the recording if currently running.
   */
  void pause() throws Exception;

  /**
   * Resumes the recording if currently paused.
   */
  void resume() throws Exception;

  /**
   * Gets the state the of recording
   *
   * @return True if recording. False otherwise.
   */
  boolean isRecording();

  /**
   * Gets the state the of recording
   *
   * @return True if paused. False otherwise.
   */
  boolean isPaused();

  /**
   * Gets the maximum amplitude
   *
   * @return Map with current and max amplitude values
   */
  Map<String, Object> getAmplitude();

  /**
   * Check if the given encoder is supported by the recorder implementation.
   *
   * @param encoder The encoder from AudioEncoder enum.
   */
  boolean isEncoderSupported(String encoder);

  /**
   * Stops recording and releases all resources.
   */
  void close();
}
