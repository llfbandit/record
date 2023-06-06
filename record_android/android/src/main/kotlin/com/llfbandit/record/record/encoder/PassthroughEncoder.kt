package com.llfbandit.record.record.encoder

import android.media.MediaCodec
import android.media.MediaFormat
import com.llfbandit.record.record.container.IContainerWriter
import com.llfbandit.record.record.format.Format
import java.nio.ByteBuffer

/**
 * Create a passthrough encoder for the specified format.
 */
class PassthroughEncoder(
    private val mediaFormat: MediaFormat,
    private val listener: EncoderListener,
    private val container: IContainerWriter
) : IEncoder {
    private var isStarted = false
    private val bufferInfo = MediaCodec.BufferInfo()
    private var trackIndex = -1

    private val frameSize = mediaFormat.getInteger(Format.KEY_X_FRAME_SIZE_IN_BYTES)
    private val sampleRate = mediaFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)

    /** Number of frames encoded so far. */
    private var numFrames = 0L

    /** Presentation timestamp given [numFrames] already being encoded */
    private val timestampUs
        get() = numFrames * 1_000_000L / sampleRate

    override fun start() {
        if (isStarted) {
            throw IllegalStateException("Encoder is already started")
        }

        isStarted = true

        EncodeThread().start()
    }

    override fun stop() {
        if (!isStarted) {
            throw IllegalStateException("Encoder is not started")
        }

        isStarted = false
    }

    override fun release() {
        if (isStarted) {
            stop()
        }
    }

    private inner class EncodeThread : Thread() {
        override fun run() = encode()

        private fun encode() {
            trackIndex = container.addTrack(mediaFormat)
            container.start()

            val buffer = ByteBuffer.allocateDirect(listener.onEncoderDataSize())

            var isEof = false

            while (isStarted || !isEof) {
                isEof = !isStarted
                buffer.clear()

                val bytesRead = listener.onEncoderDataNeeded(buffer)

                if (bytesRead > 0) {
                    val frames = buffer.remaining() / frameSize

                    bufferInfo.offset = buffer.position()
                    bufferInfo.size = buffer.limit()
                    bufferInfo.presentationTimeUs = timestampUs
                    bufferInfo.flags = if (isEof) {
                        MediaCodec.BUFFER_FLAG_END_OF_STREAM
                    } else {
                        0
                    }

                    if (!container.isStream()) {
                        container.writeSampleData(trackIndex, buffer, bufferInfo)
                    } else {
                        listener.onEncoderStream(container.writeStream(trackIndex, buffer, bufferInfo))
                    }

                    numFrames += frames
                }
            }

            container.stop()
            listener.onEncoderStop()
        }
    }
}