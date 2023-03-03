package com.llfbandit.record.record.format;

enum AacProfile {
  LC(2),    /* OMX_AUDIO_AACObjectLC */
  HE(5),    /* OMX_AUDIO_AACObjectHE */
  ELD(39);  /* OMX_AUDIO_AACObjectELD */

  final int id;

  AacProfile(int id) {
    this.id = id;
  }
}
