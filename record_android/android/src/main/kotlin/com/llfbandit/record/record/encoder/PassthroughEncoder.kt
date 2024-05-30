package com.llfbandit.record.record.encoder

import android.media.MediaCodec
import android.media.MediaFormat
import com.llfbandit.record.record.RecordConfig
import com.llfbandit.record.record.format.Format
import java.nio.ByteBuffer

/**
 * Create a passthrough encoder for the specified format.
 */
class PassthroughEncoder(
    config: RecordConfig,
    format: Format,
    private val mediaFormat: MediaFormat,
    private val listener: EncoderListener,
) : IEncoder {
    private var mIsStarted = false
    private val mBufferInfo = MediaCodec.BufferInfo()
    private var mTrackIndex = -1
    private var mContainer = format.getContainer(config.path)

    private val mFrameSize = mediaFormat.getInteger(Format.KEY_X_FRAME_SIZE_IN_BYTES)
    private val mSampleRate = mediaFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)

    /** Number of frames encoded so far. */
    private var mNumFrames = 0L

    /** Presentation timestamp given [mNumFrames] already being encoded */
    private val timestampUs
        get() = mNumFrames * 1_000_000L / mSampleRate

    override fun startEncoding() {
        if (mIsStarted) {
            return
        }

        mTrackIndex = mContainer.addTrack(mediaFormat)
        mContainer.start()

        mIsStarted = true
    }

    override fun stopEncoding() {
        if (mIsStarted) {
            mIsStarted = false
            mContainer.stop()
        }
    }

    override fun encode(bytes: ByteArray) {
        if (!mIsStarted) return

        val buffer = ByteBuffer.wrap(bytes)
        val frames = buffer.remaining() / mFrameSize

        mBufferInfo.offset = buffer.position()
        mBufferInfo.size = buffer.limit()
        mBufferInfo.presentationTimeUs = timestampUs

        if (mContainer.isStream()) {
            listener.onEncoderStream(mContainer.writeStream(mTrackIndex, buffer, mBufferInfo))
        } else {
            mContainer.writeSampleData(mTrackIndex, buffer, mBufferInfo)
        }

        mNumFrames += frames
    }
}