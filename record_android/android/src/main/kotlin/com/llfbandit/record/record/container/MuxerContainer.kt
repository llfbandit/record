package com.llfbandit.record.record.container

import android.media.MediaCodec
import android.media.MediaFormat
import android.media.MediaMuxer
import java.nio.ByteBuffer

/**
 * Wrapper around [MediaMuxer].
 *
 * @param path                             Output file path.
 * @param requiresCodecSpecificDataInFormat If true, csd-0 must be present in the [MediaFormat]
 *                                          passed to [addTrack]. If the codec delivers it via a
 *                                          [MediaCodec.BUFFER_FLAG_CODEC_CONFIG] buffer instead of
 *                                          the format, it is injected in [addTrack] automatically.
 * @param containerFormat                  A valid [MediaMuxer.OutputFormat] value.
 */
class MuxerContainer(
  val path: String,
  private val requiresCodecSpecificDataInFormat: Boolean,
  private val containerFormat: Int
) : IContainerWriter {
  private var mMuxer: MediaMuxer? = null
  private var mStarted = false
  private var mStopped = false
  private var mCsdReceived = false
  private var mPendingCsd: ByteArray? = null

  override fun start() {
    if (mStarted || mStopped) return

    mStarted = true
    mMuxer?.start()
  }

  private fun stop() {
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

    if (requiresCodecSpecificDataInFormat && !mediaFormat.containsKey("csd-0")) {
      mPendingCsd?.let { mediaFormat.setByteBuffer("csd-0", ByteBuffer.wrap(it)) }
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

  override fun onCsdBuffer(csd: ByteArray?) {
    if (!requiresCodecSpecificDataInFormat) return
    mCsdReceived = true
    mPendingCsd = csd
  }

  override fun isReadyForSetup(format: MediaFormat): Boolean {
    if (!requiresCodecSpecificDataInFormat) return true
    return format.containsKey("csd-0") || mCsdReceived
  }
}