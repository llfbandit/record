package com.llfbandit.record.record.container

import android.media.MediaCodec
import android.media.MediaFormat
import java.nio.ByteBuffer


/**
 * Abstract class for writing encoded samples to a container format.
 */
interface IContainerWriter {
  /**
   * Start the muxer process.
   *
   *
   * Must be called before [writeSampleData].
   */
  fun start()

  /**
   * Free resources used by the muxer process.
   *
   *
   * Can be called in any state. If the muxer process is started, it will be stopped.
   */
  fun release()

  /**
   * Add a track to the container with the specified format.
   *
   *
   * Must not be called after the muxer process is started.
   *
   * @param mediaFormat Must be the instance returned by [MediaCodec.getOutputFormat]
   */
  fun addTrack(mediaFormat: MediaFormat): Int

  /**
   * Write encoded samples to the output container.
   *
   *
   * Must not be called unless the muxer process is started.
   *
   * @param trackIndex Must be an index returned by [addTrack]
   */
  fun writeSampleData(trackIndex: Int, byteBuffer: ByteBuffer, bufferInfo: MediaCodec.BufferInfo)

  /**
   * Called when the codec delivers a [MediaCodec.BUFFER_FLAG_CODEC_CONFIG] buffer.
   * [csd] is null if the buffer could not be read from the codec.
   * Containers that need codec-specific data in their track format should store it here
   * and inject it in [addTrack].
   */
  fun onCsdBuffer(csd: ByteArray?) {}

  /**
   * Returns true when the container has everything it needs to accept an [addTrack] call.
   * The encoder will not call [addTrack] until this returns true.
   */
  fun isReadyForSetup(format: MediaFormat): Boolean = true
}

internal fun ByteBuffer.toByteArray(info: MediaCodec.BufferInfo): ByteArray {
  position(info.offset)
  limit(info.offset + info.size)
  return ByteArray(info.size).also { get(it) }
}
