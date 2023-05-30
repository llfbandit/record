package com.llfbandit.record.record.container

import android.media.MediaCodec
import android.media.MediaFormat
import java.io.RandomAccessFile
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
     * Stop the muxer process.
     *
     *
     * Must not be called if [start] did not complete successfully.
     */
    fun stop()

    /**
     * Free resources used by the muxer process.
     *
     *
     * Can be called in any state. If the muxer process is started, it will be stopped.
     */
    fun release()

    /**
     * Checks if the container is configured for file or stream output
     */
    fun isStream(): Boolean = false

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
     * Write encoded samples to the output container.
     *
     *
     * Must not be called unless the muxer process is started.
     *
     * @param trackIndex Must be an index returned by [addTrack]
     */
    fun writeStream(
        trackIndex: Int,
        byteBuffer: ByteBuffer,
        bufferInfo: MediaCodec.BufferInfo
    ): ByteArray {
        throw NotImplementedError()
    }

    fun createFile(path: String): RandomAccessFile {
        val out = RandomAccessFile(path, "rw")
        // Clears file content. Prevents wrong output if file was existing.
        out.setLength(0)

        return out
    }
}