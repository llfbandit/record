package com.llfbandit.record.record.format;

import android.media.MediaCodecInfo;

public enum AacProfile {
  LC(MediaCodecInfo.CodecProfileLevel.AACObjectLC),
  HE(MediaCodecInfo.CodecProfileLevel.AACObjectHE),
  ELD(MediaCodecInfo.CodecProfileLevel.AACObjectELD);

  public final int id;

  AacProfile(int id) {
    this.id = id;
  }
}
