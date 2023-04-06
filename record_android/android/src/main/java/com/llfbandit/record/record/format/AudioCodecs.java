package com.llfbandit.record.record.format;

import android.media.MediaCodec;
import android.media.MediaFormat;

public class AudioCodecs {
  public MediaCodec getAmrNbCodec(int channels, int bitRate) throws Exception {
//    final int bitRates[] = { 4750, 5150, 5900, 6700, 7400, 7950, 10200, 12200 };

    MediaFormat format = new MediaFormat();

    format.setString(MediaFormat.KEY_MIME, MediaFormat.MIMETYPE_AUDIO_AMR_NB);
    format.setInteger(MediaFormat.KEY_SAMPLE_RATE, 8000); // required by SDK
    format.setInteger(MediaFormat.KEY_CHANNEL_COUNT, channels);
    format.setInteger(MediaFormat.KEY_BIT_RATE, bitRate);

    return getMediaCodec(format);
  }

  public MediaCodec getAmrWbCodec(int channels, int bitRate) throws Exception {
//    final int bitRates[] = { 6600, 8850, 12650, 14250, 15850, 18250, 19850, 23050, 23850 };

    MediaFormat format = new MediaFormat();

    format.setString(MediaFormat.KEY_MIME, MediaFormat.MIMETYPE_AUDIO_AMR_WB);
    format.setInteger(MediaFormat.KEY_SAMPLE_RATE, 16000); // required by SDK
    format.setInteger(MediaFormat.KEY_CHANNEL_COUNT, channels);
    format.setInteger(MediaFormat.KEY_BIT_RATE, bitRate);

    return getMediaCodec(format);
  }

  public MediaCodec getAacCodec(
      int channels,
      int bitRate,
      int sampleRate,
      AacProfile profile
  ) throws Exception {
//    final int sampleRates[] = { 8000, 11025, 22050, 44100, 48000 };

    MediaFormat format = new MediaFormat();

    format.setString(MediaFormat.KEY_MIME, MediaFormat.MIMETYPE_AUDIO_AAC);
    format.setInteger(MediaFormat.KEY_AAC_PROFILE, profile.id);
    format.setInteger(MediaFormat.KEY_SAMPLE_RATE, sampleRate);
    format.setInteger(MediaFormat.KEY_CHANNEL_COUNT, channels);
    format.setInteger(MediaFormat.KEY_BIT_RATE, bitRate);

    return getMediaCodec(format);
  }

  public MediaCodec getFlacCodec(int channels, int bitRate, int sampleRate) throws Exception {
    //    final int sampleRates[] = { 8000, 11025, 22050, 44100, 48000 };

    MediaFormat format = new MediaFormat();

    format.setString(MediaFormat.KEY_MIME, MediaFormat.MIMETYPE_AUDIO_FLAC);
    format.setInteger(MediaFormat.KEY_SAMPLE_RATE, sampleRate);
    format.setInteger(MediaFormat.KEY_CHANNEL_COUNT, channels);
    format.setInteger(MediaFormat.KEY_BIT_RATE, bitRate);
    format.setInteger(MediaFormat.KEY_FLAC_COMPRESSION_LEVEL, 4);

    return getMediaCodec(format);
  }

  public MediaCodec getOpusCodec(int channels, int bitRate, int sampleRate) throws Exception {
    //    final int sampleRates[] = { 8000, 11025, 22050, 44100, 48000 };

    MediaFormat format = new MediaFormat();

    format.setString(MediaFormat.KEY_MIME, MediaFormat.MIMETYPE_AUDIO_OPUS);
    format.setInteger(MediaFormat.KEY_SAMPLE_RATE, sampleRate);
    format.setInteger(MediaFormat.KEY_CHANNEL_COUNT, channels);
    format.setInteger(MediaFormat.KEY_BIT_RATE, bitRate);

    return getMediaCodec(format);
  }

  public MediaCodec getVorbisCodec(int channels, int bitRate, int sampleRate) throws Exception {
    //    final int sampleRates[] = { 8000, 11025, 22050, 44100, 48000 };

    MediaFormat format = new MediaFormat();

    format.setString(MediaFormat.KEY_MIME, MediaFormat.MIMETYPE_AUDIO_VORBIS);
    format.setInteger(MediaFormat.KEY_SAMPLE_RATE, sampleRate);
    format.setInteger(MediaFormat.KEY_CHANNEL_COUNT, channels);
    format.setInteger(MediaFormat.KEY_BIT_RATE, bitRate);

    return getMediaCodec(format);
  }

  private MediaCodec getMediaCodec(MediaFormat format) throws Exception {
    MediaCodec codec = MediaCodec.createEncoderByType(format.getString(MediaFormat.KEY_MIME));

    try {
      codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
    } catch (Exception e) {
      codec.release();
      throw e;
    }

    return codec;
  }
}
