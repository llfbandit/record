package com.llfbandit.record.record.processor;

import android.media.MediaCodec;
import android.media.MediaMuxer;

import androidx.annotation.NonNull;

import com.llfbandit.record.record.RecordConfig;
import com.llfbandit.record.record.format.AacProfile;
import com.llfbandit.record.record.format.AudioCodecs;

import java.util.Arrays;

public class AacProcessor extends CodecProcessor {
  private final int[] sampleRates = new int[]{96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000};

  private RecordConfig config;
  private AacProfile aacProfile;

  public AacProcessor(@NonNull OnAudioProcessorListener listener) {
    super(listener);
  }

  @Override
  public MediaCodec createCodec(RecordConfig config) throws Exception {
    checkAllowedSampleRate(config.samplingRate);

    this.config = config;

    AudioCodecs codecs = new AudioCodecs();

    switch (config.encoder) {
      case "aacLc":
        aacProfile = AacProfile.LC;
        break;
      case "aacEld":
        aacProfile = AacProfile.ELD;
        break;
      case "aacHe":
        aacProfile = AacProfile.HE;
        break;
      default:
        throw new Exception("Unknown encoder: " + config.encoder);
    }

    return codecs.getAacCodec(config.numChannels, config.bitRate, config.samplingRate, aacProfile);
  }

  @Override
  public MediaMuxer createMuxer(@NonNull String path) throws Exception {
    return new MediaMuxer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
  }

  @Override
  public void onStream(byte[] buffer, @NonNull MediaCodec.BufferInfo info) {
    listener.onAudioChunk(addADTSFrame(info.size, config.samplingRate, config.numChannels));
    listener.onAudioChunk(buffer);
  }

  /**
   * Add ADTS frame at the beginning of each and every AAC frame.
   * Note the bufferLen must **NOT** count in the ADTS frame itself.
   **/
  private byte[] addADTSFrame(int bufferLen, int sampleRate, int channels) {
    final byte[] frame = new byte[7];
    int frameLen = bufferLen + 7;

    int profile;
    if (aacProfile == AacProfile.ELD) profile = 39;
    else if (aacProfile == AacProfile.HE) profile = 29;
    else /*if (aacProfile == AacProfile.HE)*/ profile = 2;

    int freqIdx = getFreqIndex(sampleRate);

    frame[0] = (byte) 0xFF;
    frame[1] = (byte) 0xF9;
    frame[2] = (byte) (((profile - 1) << 6) + (freqIdx << 2) + (channels >> 2));
    frame[3] = (byte) (((channels & 3) << 6) + (frameLen >> 11));
    frame[4] = (byte) ((frameLen & 0x7FF) >> 3);
    frame[5] = (byte) (((frameLen & 7) << 5) + 0x1F);
    frame[6] = (byte) 0xFC;

    return frame;
  }

  private int getFreqIndex(int sampleRate) {
    for (int i = 0; i < sampleRates.length; i++) {
      if (sampleRates[i] == sampleRate) {
        return i;
      }
    }

    return 4; // 44100 Hz
  }

  private void checkAllowedSampleRate(int sampleRate) throws Exception {
    for (int rate : sampleRates) {
      if (rate == sampleRate) {
        return;
      }
    }

    throw new Exception("Allowed sample rates are: " + Arrays.toString(sampleRates));
  }
}
