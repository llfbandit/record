package com.llfbandit.record.record;

import androidx.annotation.NonNull;

import java.util.Map;

public class RecordConfig {
  final String path;
  final String encoder;
  final int bitRate;
  final int samplingRate;
  final int numChannels;
  final Map<String, Object> device;
  final boolean noiseCancel;
  final boolean autoGain;

  /**
   * @param path         The output path to write the file.
   * @param encoder      The encoder enum index from dart side.
   * @param bitRate      The bit rate of encoded file.
   * @param samplingRate The sampling rate of encoded file.
   * @param numChannels  The number of channels (1 or 2).
   * @param device       The input device to acquire audio data.
   * @param noiseCancel  Enables noise cancellation if available.
   * @param autoGain     Enables automatic gain control if available.
   */
  public RecordConfig(
      String path,
      @NonNull String encoder,
      int bitRate,
      int samplingRate,
      int numChannels,
      Map<String, Object> device,
      boolean noiseCancel,
      boolean autoGain
  ) {
    this.path = path;
    this.encoder = encoder;
    this.bitRate = bitRate;
    this.samplingRate = samplingRate;
    this.numChannels = Math.min(2, Math.max(1, numChannels));
    this.device = device;
    this.noiseCancel = noiseCancel;
    this.autoGain = autoGain;
  }
}
