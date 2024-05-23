/// Audio encoder to be used for recording.
enum AudioEncoder {
  /// MPEG-4 AAC Low complexity
  /// Will output to MPEG_4 format container.
  ///
  /// Suggested file extension: `m4a`
  aacLc,

  /// MPEG-4 AAC Enhanced Low Delay
  /// Will output to MPEG_4 format container.
  ///
  /// Suggested file extension: `m4a`
  aacEld,

  /// MPEG-4 High Efficiency AAC (Version 2 if available)
  /// Will output to MPEG_4 format container.
  ///
  /// Suggested file extension: `m4a`
  aacHe,

  /// The AMR (Adaptive Multi-Rate) narrow band speech.
  /// sampling rate should be set to 8kHz.
  /// Will output to 3GP format container on Android.
  ///
  /// Suggested file extension: `3gp`
  amrNb,

  /// The AMR (Adaptive Multi-Rate) wide band speech.
  /// sampling rate should be set to 16kHz.
  /// Will output to 3GP format container on Android.
  ///
  /// Suggested file extension: `3gp`
  amrWb,

  /// Will output to OGG format container.
  ///
  /// SDK 29 on Android
  ///
  /// Suggested file extension: `opus`
  opus,

  /// Free Lossless Audio Codec
  ///
  /// /// Suggested file extension: `flac`
  flac,

  /// Waveform Audio (pcm16bit with headers)
  ///
  /// Suggested file extension: `wav`
  wav,

  /// Linear PCM 16 bit per sample
  ///
  /// Suggested file extension: `pcm`
  pcm16bits,
}
