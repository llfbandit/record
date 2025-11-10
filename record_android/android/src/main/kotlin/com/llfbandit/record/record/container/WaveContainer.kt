package com.llfbandit.record.record.container

import android.media.MediaCodec
import android.media.MediaFormat
import android.system.Os
import android.system.OsConstants
import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder

class WaveContainer(path: String, private val frameSize: Int) : IContainerWriter {
  private val file = createFile(path)

  private var isStarted = false
  private var track = -1
  private var channelCount = 0
  private var sampleRate = 0

  override fun start() {
    if (isStarted) {
      throw IllegalStateException("Container already started")
    }

    Os.ftruncate(file.fd, 0)

    // Skip header
    Os.lseek(file.fd, HEADER_SIZE.toLong(), OsConstants.SEEK_SET)

    isStarted = true
  }

  override fun stop() {
    if (!isStarted) {
      throw IllegalStateException("Container not started")
    }

    isStarted = false

    if (track >= 0) {
      val fileSize = Os.lseek(file.fd, 0, OsConstants.SEEK_CUR)
      val header = buildHeader(fileSize)
      Os.lseek(file.fd, 0, OsConstants.SEEK_SET)
      Os.write(file.fd, header)
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
    channelCount = mediaFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
    sampleRate = mediaFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)

    return track
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

  private fun buildHeader(fileSize: Long): ByteBuffer {
    return ByteBuffer.allocate(HEADER_SIZE).apply {
      order(ByteOrder.LITTLE_ENDIAN)

      val (chunkSize, dataSize) = if (fileSize > MAX_FILE_SIZE - HEADER_SIZE) {
        Log.w(TAG, "File is oversized! WAV files can only fit in 4GB max.")
        Pair(MAX_FILE_SIZE - 8, MAX_FILE_SIZE - HEADER_SIZE)
      } else {
        Pair(fileSize - 8, fileSize - HEADER_SIZE)
      }

      // 0-3: Chunk ID
      put(RIFF_MAGIC)
      // 4-7: Chunk size
      put(longToUInt32(chunkSize))
      // 8-11: Format
      put(WAVE_MAGIC)
      // 12-15: Subchunk 1 ID
      put(FMT_MAGIC)
      // 16-19: Subchunk 1 size
      putInt(16)
      // 20-21: Audio format
      putShort(1)
      // 22-23: Number of channels
      putShort(channelCount.toShort())
      // 24-27: Sample rate
      putInt(sampleRate)
      // 28-31: Byte rate
      putInt(sampleRate * frameSize)
      // 32-33: Block align
      putShort(frameSize.toShort())
      // 34-35: Bits per sample
      putShort(((frameSize / channelCount) * 8).toShort())
      // 36-39: Subchunk 2 ID
      put(DATA_MAGIC)
      // 40-43: Subchunk 2 size
      put(longToUInt32(dataSize))

      flip()
    }
  }

  private fun longToUInt32(value: Long): ByteArray {
    val bytes = ByteArray(4)
    bytes[0] = (value and 0xFF).toByte()
    bytes[1] = ((value shr 8) and 0xFF).toByte()
    bytes[2] = ((value shr 16) and 0xFF).toByte()
    bytes[3] = ((value shr 24) and 0xFF).toByte()
    return bytes
  }

  companion object {
    private val TAG = WaveContainer::class.java.simpleName

    private const val HEADER_SIZE = 44
    private const val MAX_FILE_SIZE = 4_294_967_296L - 1
    private val RIFF_MAGIC = byteArrayOf(0x52, 0x49, 0x46, 0x46) // RIFF
    private val WAVE_MAGIC = byteArrayOf(0x57, 0x41, 0x56, 0x45) // WAVE
    private val FMT_MAGIC = byteArrayOf(0x66, 0x6d, 0x74, 0x20) // "fmt "
    private val DATA_MAGIC = byteArrayOf(0x64, 0x61, 0x74, 0x61) // data
  }
}