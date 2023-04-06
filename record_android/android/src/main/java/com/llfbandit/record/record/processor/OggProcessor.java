package com.llfbandit.record.record.processor;

import android.media.MediaCodec;
import android.media.MediaMuxer;
import android.os.Build;

import androidx.annotation.NonNull;

import com.llfbandit.record.record.RecordConfig;
import com.llfbandit.record.record.format.AudioCodecs;

public class OggProcessor extends CodecProcessor {
  public OggProcessor(@NonNull OnAudioProcessorListener listener) {
    super(listener);
  }

  @Override
  public MediaCodec createCodec(RecordConfig config) throws Exception {
    if (config.path == null) {
      throw new Exception("Ogg must be recorded into file. Given path is null.");
    }

    AudioCodecs codecs = new AudioCodecs();

    if ("vorbisOgg".equals(config.encoder)) {
      return codecs.getVorbisCodec(config.numChannels, config.bitRate, config.samplingRate);
    }

    throw new Exception("Unknown encoder: " + config.encoder);
  }

  @Override
  public MediaMuxer createMuxer(@NonNull String path) throws Exception {
    return new MediaMuxer(path, (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
        ? MediaMuxer.OutputFormat.MUXER_OUTPUT_OGG
        : MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
  }

  @Override
  public void onStream(byte[] buffer, @NonNull MediaCodec.BufferInfo info) throws Exception {
    throw new Exception("OGG stream is not supported.");
  }
}
