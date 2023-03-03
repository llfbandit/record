package com.llfbandit.record.record.format;

import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaFormat;

import java.util.ArrayList;
import java.util.List;

public class AudioFormats {
  private AudioFormats() {
  }

  static List<String> getEncoderNamesForType(String mime) {
    List<String> names = new ArrayList<>();

    int n = MediaCodecList.getCodecCount();

    for (int i = 0; i < n; ++i) {
      MediaCodecInfo info = MediaCodecList.getCodecInfoAt(i);
      if (!info.isEncoder()) {
        continue;
      }

      if (!info.getName().startsWith("OMX.")) {
        // Unfortunately for legacy reasons, "AACEncoder", a
        // non OMX component had to be in this list for the video
        // editor code to work... but it cannot actually be instantiated
        // using MediaCodec.
        continue;
      }

      String[] supportedTypes = info.getSupportedTypes();
      for (String supportedType : supportedTypes) {
        if (supportedType.equalsIgnoreCase(mime)) {
          names.add(info.getName());
          break;
        }
      }
    }
    return names;
  }

  static MediaFormat getAmrNbFormat(int channels, int bitRate) {
//    final int bitRates[] = { 4750, 5150, 5900, 6700, 7400, 7950, 10200, 12200 };

    MediaFormat format = new MediaFormat();

    format.setString(MediaFormat.KEY_MIME, "audio/3gpp");
    format.setInteger(MediaFormat.KEY_SAMPLE_RATE, 8000); // required by SDK
    format.setInteger(MediaFormat.KEY_CHANNEL_COUNT, channels);
    format.setInteger(MediaFormat.KEY_BIT_RATE, bitRate);

    return format;
  }

  static MediaFormat getAmrWbFormat(int channels, int bitRate) {
//    final int bitRates[] = { 6600, 8850, 12650, 14250, 15850, 18250, 19850, 23050, 23850 };

    MediaFormat format = new MediaFormat();

    format.setString(MediaFormat.KEY_MIME, "audio/amr-wb");
    format.setInteger(MediaFormat.KEY_SAMPLE_RATE, 16000); // required by SDK
    format.setInteger(MediaFormat.KEY_CHANNEL_COUNT, channels);
    format.setInteger(MediaFormat.KEY_BIT_RATE, bitRate);

    return format;
  }

  static MediaFormat getAacFormat(int channels, int bitRate, int sampleRate, AacProfile profile) {
//    final int sampleRates[] = { 8000, 11025, 22050, 44100, 48000 };

    MediaFormat format = new MediaFormat();

    format.setString(MediaFormat.KEY_MIME, "audio/mp4a-latm");
    format.setInteger(MediaFormat.KEY_AAC_PROFILE, profile.id);
    format.setInteger(MediaFormat.KEY_SAMPLE_RATE, sampleRate);
    format.setInteger(MediaFormat.KEY_CHANNEL_COUNT, channels);
    format.setInteger(MediaFormat.KEY_BIT_RATE, bitRate);

    return format;
  }
}
