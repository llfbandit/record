package com.llfbandit.record.record.container

import android.media.MediaCodec
import android.media.MediaFormat
import android.system.Os
import android.system.OsConstants
import java.io.IOException
import java.nio.ByteBuffer

@OptIn(ExperimentalUnsignedTypes::class)
class FlacContainer(path: String) : IContainerWriter {
    private val file = createFile(path)

    private var isStarted = false
    private var lastPresentationTimeUs = -1L
    private var track = -1

    override fun start() {
        if (isStarted) {
            throw IllegalStateException("Container already started")
        }

        Os.lseek(file.fd, 0, OsConstants.SEEK_SET)
        Os.ftruncate(file.fd, 0)

        isStarted = true
    }

    override fun stop() {
        check(isStarted) { "Container not started" }

        isStarted = false

        if (lastPresentationTimeUs >= 0) {
            setHeaderDuration()
        }

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

        if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
            lastPresentationTimeUs = bufferInfo.presentationTimeUs
        }
    }

    /**
     * Write the frame count to the STREAMINFO metadata block of a flac file.
     *
     * @throws IOException If FLAC metadata does not appear to be valid or if the number of frames
     * computed from [lastPresentationTimeUs] exceeds the bounds of a 36-bit integer
     */
    private fun setHeaderDuration() {
        Os.lseek(file.fd, 0, OsConstants.SEEK_SET)

        // Magic (4 bytes)
        // + metadata block header (4 bytes)
        // + streaminfo block (34 bytes)
        val buf = UByteArray(42)

        if (Os.read(file.fd, buf.asByteArray(), 0, buf.size) != buf.size) {
            throw IOException("EOF reached when reading FLAC headers")
        }

        // Validate the magic
        if (ByteBuffer.wrap(buf.asByteArray(), 0, 4) !=
            ByteBuffer.wrap(FLAC_MAGIC.asByteArray())
        ) {
            throw IOException("FLAC magic not found")
        }

        // Validate that the first metadata block is STREAMINFO and has the correct size
        if (buf[4] and 0x7fu != 0.toUByte()) {
            throw IOException("First metadata block is not STREAMINFO")
        }

        val streamInfoSize = buf[5].toUInt().shl(16) or
                    buf[6].toUInt().shl(8) or
                    buf[7].toUInt()
        if (streamInfoSize < 34u) {
            throw IOException("STREAMINFO block is too small")
        }

        // Sample rate field is a 20-bit integer at the 18th byte
        val sampleRate = buf[18].toUInt().shl(12) or
                buf[19].toUInt().shl(4) or
                buf[20].toUInt().shr(4)

        // This underestimates the duration by a miniscule amount because it doesn't account for the
        // duration of the final write
        val frames = lastPresentationTimeUs.toULong() * sampleRate / 1_000_000uL

        if (frames >= 2uL.shl(36)) {
            throw IOException("Frame count cannot be represented in FLAC: $frames")
        }

        // Total samples field is a 36-bit integer that begins 4 bits into the 21st byte
        buf[21] = (buf[21] and 0xf0u) or (frames.shr(32) and 0xfu).toUByte()
        buf[22] = (frames.shr(24) and 0xffu).toUByte()
        buf[23] = (frames.shr(16) and 0xffu).toUByte()
        buf[24] = (frames.shr(8) and 0xffu).toUByte()
        buf[25] = (frames and 0xffu).toUByte()

        Os.lseek(file.fd, 21, OsConstants.SEEK_SET)
        if (Os.write(file.fd, buf.asByteArray(), 21, 5) != 5) {
            throw IOException("EOF reached when writing frame count")
        }
    }

    companion object {
        private val FLAC_MAGIC = ubyteArrayOf(0x66u, 0x4cu, 0x61u, 0x43u) // fLaC
    }
}