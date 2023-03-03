package com.llfbandit.record.record.processing;

import android.media.MediaCodec;

import java.nio.ByteBuffer;

public class AudioEncoder {
  private MediaCodec mediaCodec;

  private int queueInputBuffer(MediaCodec codec,
                               ByteBuffer[] inputBuffers,
                               int index
  ) {
    ByteBuffer buffer = inputBuffers[index];
    buffer.clear();
    int size = buffer.limit();
    byte[] zeroes = new byte[size];
    buffer.put(zeroes);
    codec.queueInputBuffer(index, 0 /* offset */, size, 0 /* timeUs */, 0);
    return size;
  }

  private void dequeueOutputBuffer(MediaCodec codec,
                                   ByteBuffer[] outputBuffers,
                                   int index,
                                   MediaCodec.BufferInfo info
  ) {
    codec.releaseOutputBuffer(index, false /* render */);
  }

}
