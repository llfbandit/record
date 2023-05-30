package com.llfbandit.record.record.container

import android.media.MediaCodec
import android.media.MediaFormat
import android.system.Os
import java.nio.ByteBuffer

class RawContainer(path: String) : IContainerWriter {
    private val file = createFile(path)

    private var isStarted = false
    private var track = -1

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
        file.close()
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

        Os.write(file.fd, byteBuffer)
    }
}