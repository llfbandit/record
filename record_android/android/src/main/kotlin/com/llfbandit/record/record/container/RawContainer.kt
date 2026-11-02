package com.llfbandit.record.record.container

import android.media.MediaCodec
import android.media.MediaFormat
import java.nio.ByteBuffer

class RawContainer(path: String) : FileContainer(path)

class RawStreamContainer(private val onChunk: (ByteArray) -> Unit) : IContainerWriter {
  override fun start() {}
  override fun release() {}
  override fun addTrack(mediaFormat: MediaFormat) = 0

  override fun writeSampleData(trackIndex: Int, byteBuffer: ByteBuffer, bufferInfo: MediaCodec.BufferInfo) {
    onChunk(byteBuffer.toByteArray(bufferInfo))
  }
}
