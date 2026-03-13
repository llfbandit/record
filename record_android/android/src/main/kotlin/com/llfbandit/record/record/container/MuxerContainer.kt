package com.llfbandit.record.record.container

import android.media.MediaCodec
import android.media.MediaFormat
import android.media.MediaMuxer
import java.nio.ByteBuffer

/**
 * Wrapper around [MediaMuxer].
 *
 * @param path            Output file path.
 * @param ignoreCodecSpecificData If true, ignores samples flagged as [MediaCodec.BUFFER_FLAG_CODEC_CONFIG].
 * @param containerFormat A valid [MediaMuxer.OutputFormat] value for the output container format.
 */
class MuxerContainer(
  val path: String,
  val ignoreCodecSpecificData: Boolean,
  private val containerFormat: Int
) : IContainerWriter {
  private var mMuxer: MediaMuxer? = null
  private var mStarted = false
  private var mStopped = false

  override fun start() {
    if (mStarted || mStopped) return

    mStarted = true
    mMuxer?.start()
  }

  override fun stop() {
    if (!mStarted || mStopped) return

    mStarted = false
    mStopped = true
    mMuxer?.stop()
  }

  override fun addTrack(mediaFormat: MediaFormat): Int {
    if (mStarted || mStopped) return -1

    if (mMuxer == null) {
      mMuxer = MediaMuxer(path, containerFormat)
    }

    return mMuxer!!.addTrack(mediaFormat)
  }

  override fun writeSampleData(
    trackIndex: Int,
    byteBuffer: ByteBuffer,
    bufferInfo: MediaCodec.BufferInfo
  ) {
    if (!mStarted || mStopped) return

    mMuxer?.writeSampleData(trackIndex, byteBuffer, bufferInfo)
  }

  override fun release() {
    stop()

    mMuxer?.release()
    mMuxer = null
  }

  override fun ignoreCodecSpecificData(): Boolean {
    return ignoreCodecSpecificData
  }
}