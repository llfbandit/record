package com.llfbandit.record.record.processor;

import android.media.MediaCodec;
import android.media.MediaMuxer;

import androidx.annotation.NonNull;

import com.llfbandit.record.record.RecordConfig;
import com.llfbandit.record.record.format.AudioCodecs;

public class OpusProcessor extends CodecProcessor {
  public OpusProcessor(@NonNull OnAudioProcessorListener listener) {
    super(listener);
  }

  @Override
  public MediaCodec createCodec(RecordConfig config) throws Exception {
    if (config.path == null) {
      throw new Exception("Opus must be recorded into file. Given path is null.");
    }

    AudioCodecs codecs = new AudioCodecs();

    if ("opus".equals(config.encoder)) {
      return codecs.getOpusCodec(config.numChannels, config.bitRate, config.samplingRate);
    }

    throw new Exception("Unknown encoder: " + config.encoder);
  }

  @Override
  public MediaMuxer createMuxer(@NonNull String path) throws Exception {
    return new MediaMuxer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
  }

  @Override
  public void onStream(byte[] buffer, @NonNull MediaCodec.BufferInfo info) throws Exception {
    throw new Exception("OGG stream is not supported.");
  }
}
