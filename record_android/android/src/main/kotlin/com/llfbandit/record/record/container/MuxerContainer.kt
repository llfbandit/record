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
class MuxerContainer(val path: String, private val containerFormat: Int) : IContainerWriter {
    private var mMuxer: MediaMuxer? = null
    private var mStarted = AtomicBoolean(false)
    private var mStopped = AtomicBoolean(false)

    override fun start() {
        if (mStarted.get() || mStopped.get()) return

        mStarted.set(true)

        mMuxer?.start()
    }

    override fun stop() {
        if (!mStarted.get() || mStopped.get()) return

        mStarted.set(false)
        mStopped.set(true)

        mMuxer?.stop()
    }

    override fun addTrack(mediaFormat: MediaFormat): Int {
        if (mStarted.get() || mStopped.get()) return -1

        mMuxer = MediaMuxer(path, containerFormat)

        return mMuxer!!.addTrack(mediaFormat)
    }

    override fun writeSampleData(
        trackIndex: Int,
        byteBuffer: ByteBuffer,
        bufferInfo: MediaCodec.BufferInfo
    ) {
        if (!mStarted.get() || mStopped.get()) return

        mMuxer?.writeSampleData(trackIndex, byteBuffer, bufferInfo)
    }

    override fun release() {
        stop()

        mMuxer?.release()
        mMuxer = null
    }
}