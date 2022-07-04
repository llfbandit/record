package com.llfbandit.record;

import androidx.annotation.NonNull;

import java.util.Map;

import io.flutter.plugin.common.MethodChannel;

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
   * @param result       Always null
   */
  void start(
      @NonNull String path,
      String encoder,
      int bitRate,
      int samplingRate,
      int numChannels,
      Map<String, Object> device,
      @NonNull MethodChannel.Result result);

  /**
   * Stops the recording.
   *
   * @param result Always null
   */
  void stop(@NonNull MethodChannel.Result result);

  /**
   * Pauses the recording if currently running.
   *
   * @param result Always null
   */
  void pause(@NonNull MethodChannel.Result result);

  /**
   * Resumes the recording if currently paused.
   *
   * @param result Always null
   */
  void resume(@NonNull MethodChannel.Result result);

  /**
   * Gets the state the of recording
   *
   * @param result True if recording. False otherwise.
   */
  void isRecording(@NonNull MethodChannel.Result result);

  /**
   * Gets the state the of recording
   *
   * @param result True if paused. False otherwise.
   */
  void isPaused(@NonNull MethodChannel.Result result);

  /**
   * Gets the maximum amplitude
   *
   * @param result Map with current and max amplitude values
   */
  void getAmplitude(@NonNull MethodChannel.Result result);

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
