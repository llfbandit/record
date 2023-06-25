package com.llfbandit.record.record.container

import android.media.MediaCodec
import android.media.MediaFormat
import android.media.MediaMuxer
import java.nio.ByteBuffer

/**
 * Wrapper around [MediaMuxer].
 *
 * @param path            Output file path.
 * @param containerFormat A valid [MediaMuxer.OutputFormat] value for the output container format.
 */
class MuxerContainer(path: String, containerFormat: Int) : IContainerWriter {
    private val muxer = MediaMuxer(path, containerFormat)

    override fun start() = muxer.start()

    override fun stop() = muxer.stop()

    override fun release() = muxer.release()

    override fun addTrack(mediaFormat: MediaFormat): Int = muxer.addTrack(mediaFormat)

    override fun writeSampleData(
        trackIndex: Int,
        byteBuffer: ByteBuffer,
        bufferInfo: MediaCodec.BufferInfo
    ) = muxer.writeSampleData(trackIndex, byteBuffer, bufferInfo)
}