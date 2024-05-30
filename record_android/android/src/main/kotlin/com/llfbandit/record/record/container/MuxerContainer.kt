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
    private val mMuxer = MediaMuxer(path, containerFormat)
    private var mIsStarted = false

    override fun start() {
        if (mIsStarted) return

        mMuxer.start()
        mIsStarted = true
    }

    override fun stop() {
        if (!mIsStarted) return

        mMuxer.stop()
        mIsStarted = false
    }

    override fun release() {
        mMuxer.release()
        mIsStarted = false
    }

    override fun addTrack(mediaFormat: MediaFormat): Int = mMuxer.addTrack(mediaFormat)

    override fun writeSampleData(
        trackIndex: Int,
        byteBuffer: ByteBuffer,
        bufferInfo: MediaCodec.BufferInfo
    ) {
        if (!mIsStarted) return
        mMuxer.writeSampleData(trackIndex, byteBuffer, bufferInfo)
    }
}