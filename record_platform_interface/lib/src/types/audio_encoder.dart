/// Audio encoder to be used for recording.
enum AudioEncoder {
  /// Will output to MPEG_4 format container.
  AAC,

  /// Will output to MPEG_4 format container.
  AAC_LD,

  /// Will output to MPEG_4 format container.
  AAC_HE,

  /// sampling rate should be set to 8kHz.
  /// Will output to 3GP format container on Android.
  AMR_NB,

  /// sampling rate should be set to 16kHz.
  /// Will output to 3GP format container on Android.
  AMR_WB,

  /// Will output to MPEG_4 format container.
  /// /!\ SDK 29 on Android /!\
  /// /!\ SDK 11 on iOs /!\
  OPUS,
}
