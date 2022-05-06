/// Audio encoder to be used for recording.
enum AudioEncoder {
  /// MPEG-4 AAC Low complexity
  /// Will output to MPEG_4 format container.
  aacLc,

  /// MPEG-4 AAC Enhanced Low Delay
  /// Will output to MPEG_4 format container.
  aacEld,

  /// MPEG-4 High Efficiency AAC (Version 2 if available)
  /// Will output to MPEG_4 format container.
  aacHe,

  /// The AMR (Adaptive Multi-Rate) narrow band speech.
  /// sampling rate should be set to 8kHz.
  /// Will output to 3GP format container on Android.
  amrNb,

  /// The AMR (Adaptive Multi-Rate) wide band speech.
  /// sampling rate should be set to 16kHz.
  /// Will output to 3GP format container on Android.
  amrWb,

  /// Will output to MPEG_4 format container.
  ///
  /// SDK 29 on Android
  ///
  /// SDK 11 on iOs
  opus,

  /// Ogg Vorbis Audio
  vorbisOgg,

  /// Free Lossless Audio Codec
  flac,

  /// Waveform Audio (pcm16bit with headers)
  wav,

  /// Linear PCM 8 bit per sample
  pcm8bit,

  /// Linear PCM 16 bit per sample
  pcm16bit,
}
