package com.llfbandit.record.record.container

import android.media.MediaCodec
import android.media.MediaFormat
import android.system.Os
import java.io.RandomAccessFile
import java.nio.ByteBuffer

class RawContainer(private val path: String?) : IContainerWriter {
    private var file: RandomAccessFile? = null

    private var isStarted = false
    private var track = -1

    init {
        if (path != null) {
            file = createFile(path)
        }
    }

    override fun isStream(): Boolean = path == null

    override fun start() {
        if (isStarted) {
            throw IllegalStateException("Container already started")
        }

        isStarted = true
    }

    override fun stop() {
        if (!isStarted) {
            throw IllegalStateException("Container not started")
        }

        isStarted = false
        file?.close()
    }

    override fun release() {
        if (isStarted) {
            stop()
        }
    }

    override fun addTrack(mediaFormat: MediaFormat): Int {
        if (isStarted) {
            throw IllegalStateException("Container already started")
        } else if (track >= 0) {
            throw IllegalStateException("Track already added")
        }

        track = 0

        return this.track
    }

    override fun writeSampleData(
        trackIndex: Int,
        byteBuffer: ByteBuffer,
        bufferInfo: MediaCodec.BufferInfo
    ) {
        if (!isStarted) {
            throw IllegalStateException("Container not started")
        } else if (track < 0) {
            throw IllegalStateException("No track has been added")
        } else if (track != trackIndex) {
            throw IllegalStateException("Invalid track: $trackIndex")
        }

        if (file != null) {
            Os.write(file!!.fd, byteBuffer)
        }
    }

    override fun writeStream(
        trackIndex: Int,
        byteBuffer: ByteBuffer,
        bufferInfo: MediaCodec.BufferInfo
    ): ByteArray {
        val buffer = ByteArray(bufferInfo.size)
        byteBuffer[buffer, bufferInfo.offset, bufferInfo.size]

        return buffer
    }
}