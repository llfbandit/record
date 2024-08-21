package com.llfbandit.record.record.container

import android.media.MediaCodec
import android.media.MediaFormat
import android.media.MediaMuxer
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Wrapper around [MediaMuxer].
 *
 * @param path            Output file path.
 * @param containerFormat A valid [MediaMuxer.OutputFormat] value for the output container format.
 */
class MuxerContainer(path: String, containerFormat: Int) : IContainerWriter {
    private val mMuxer = MediaMuxer(path, containerFormat)
    private var mStarted = AtomicBoolean(false)
    private var mFinished = AtomicBoolean(false)

    override fun start() {
        if (mStarted.get() || mFinished.get()) return

        mMuxer.start()
        mStarted.set(true)
    }

    override fun stop() {
        if (!mStarted.get() || mFinished.get()) return

        mMuxer.stop()

        mStarted.set(false)
        mFinished.set(true)
    }

    override fun addTrack(mediaFormat: MediaFormat): Int {
        if (mStarted.get() || mFinished.get()) return -1

        return mMuxer.addTrack(mediaFormat)
    }

    override fun writeSampleData(
        trackIndex: Int,
        byteBuffer: ByteBuffer,
        bufferInfo: MediaCodec.BufferInfo
    ) {
        if (!mStarted.get() || mFinished.get()) return

        mMuxer.writeSampleData(trackIndex, byteBuffer, bufferInfo)
    }

    override fun release() {
        stop()
        mMuxer.release()
    }
}