package com.llfbandit.record.record;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.util.Map;

public class RecordConfig {
  @Nullable
  public final String path;
  @NonNull
  public final String encoder;
  public final int bitRate;
  public final int samplingRate;
  public final int numChannels;
  @Nullable
  public final Map<String, Object> device;
  public final boolean noiseCancel;
  public final boolean autoGain;

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
      @Nullable String path,
      @NonNull String encoder,
      int bitRate,
      int samplingRate,
      int numChannels,
      @Nullable Map<String, Object> device,
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
