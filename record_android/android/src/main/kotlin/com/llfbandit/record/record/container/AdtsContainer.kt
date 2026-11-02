package com.llfbandit.record.record.container

import android.media.MediaCodec
import android.media.MediaFormat
import java.nio.ByteBuffer

class AdtsContainer(
  private val sampleRate: Int,
  private val numChannels: Int,
  private val aacProfile: Int,
  private val onChunk: (ByteArray) -> Unit,
) : IContainerWriter {
  private val sampleRates = intArrayOf(
    96000,
    88200,
    64000,
    48000,
    44100,
    32000,
    24000,
    22050,
    16000,
    12000,
    11025,
    8000
  )

  override fun start() {}
  override fun release() {}
  override fun addTrack(mediaFormat: MediaFormat) = 0

  override fun writeSampleData(
    trackIndex: Int,
    byteBuffer: ByteBuffer,
    bufferInfo: MediaCodec.BufferInfo
  ) {
    onChunk(buildADTSHeader(bufferInfo.size) + byteBuffer.toByteArray(bufferInfo))
  }

  /**
   * Add ADTS frame at the beginning of each and every AAC frame.
   * Note the bufferLen must **NOT** count in the ADTS frame itself.
   */
  private fun buildADTSHeader(bufferLen: Int): ByteArray {
    val frame = ByteArray(7)
    val frameLen = bufferLen + 7

    val freqIdx: Int = getFreqIndex(sampleRate)
    frame[0] = 0xFF.toByte()
    frame[1] = 0xF9.toByte()
    frame[2] = ((aacProfile - 1 shl 6) + (freqIdx shl 2) + (numChannels shr 2)).toByte()
    frame[3] = ((numChannels and 3 shl 6) + (frameLen shr 11)).toByte()
    frame[4] = (frameLen and 0x7FF shr 3).toByte()
    frame[5] = ((frameLen and 7 shl 5) + 0x1F).toByte()
    frame[6] = 0xFC.toByte()

    return frame
  }

  private fun getFreqIndex(sampleRate: Int): Int {
    return sampleRates.indexOf(sampleRate)
  }
}
