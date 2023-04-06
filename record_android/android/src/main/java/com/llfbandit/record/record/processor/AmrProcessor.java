package com.llfbandit.record.record.processor;

import android.media.MediaCodec;
import android.media.MediaMuxer;
import android.os.Build;

import androidx.annotation.NonNull;
import androidx.annotation.RequiresApi;

import com.llfbandit.record.record.RecordConfig;
import com.llfbandit.record.record.format.AudioCodecs;

public class AmrProcessor extends CodecProcessor {
  public AmrProcessor(@NonNull OnAudioProcessorListener listener) {
    super(listener);
  }

  @Override
  public MediaCodec createCodec(RecordConfig config) throws Exception {
    checkApiRequirement();

    if (config.path == null) {
      throw new Exception("Amr must be recorded into file. Given path is null.");
    }

    AudioCodecs codecs = new AudioCodecs();

    switch (config.encoder) {
      case "amrNb":
        return codecs.getAmrNbCodec(config.numChannels, config.bitRate);
      case "amrWb":
        return codecs.getAmrWbCodec(config.numChannels, config.bitRate);
      default:
        throw new Exception("Unknown encoder: " + config.encoder);
    }
  }

  @Override
  @RequiresApi(api = Build.VERSION_CODES.O)
  public MediaMuxer createMuxer(@NonNull String path) throws Exception {
    checkApiRequirement();

    return new MediaMuxer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_3GPP);
  }

  @Override
  public void onStream(byte[] buffer, @NonNull MediaCodec.BufferInfo info) throws Exception {
    throw new Exception("Raw AMR stream is not supported.");
  }

  private void checkApiRequirement() throws Exception {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      throw new Exception("Amr/3GPP is available from Android API: " + Build.VERSION_CODES.O);
    }
  }
}
