package com.llfbandit.record.record.encoder

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import com.llfbandit.record.record.RecordConfig
import com.llfbandit.record.record.container.IContainerWriter
import com.llfbandit.record.record.format.Format
import java.util.LinkedList
import java.util.concurrent.Semaphore
import kotlin.math.min

class MediaCodecEncoder(
  private val config: RecordConfig,
  private val format: Format,
  private val mediaFormat: MediaFormat,
  private val listener: EncoderListener,
  private val codecName: String,
) : IEncoder,
  HandlerThread("MediaCodecEncoder Thread") {
  private var mHandler: Handler? = null
  private var mCodec: MediaCodec? = null
  private var mContainer: IContainerWriter? = null
  private val mQueue = LinkedList<Sample>()
  private var mRate = 0f // bytes per us
  private var mInputBufferPosition: Long = 0
  private var mInputBufferIndex = -1
  private var mContainerTrack = 0

  // Semaphore to signal the end of encoding
  private var mStoppedCompleter: Semaphore? = null
  private var mStopped = false

  override fun encode(bytes: ByteArray) {
    if (mStopped) {
      return
    }

    val s = Sample(bytes)
    mHandler?.post {
      if (!mStopped) {
        mQueue.add(s)
        if (mInputBufferIndex >= 0) {
          processInputBuffer()
        }
      }
    }
  }

  override fun startEncoding() {
    start() // Start the thread
    mHandler = Handler(looper)
    mHandler?.post { initEncoding() }
  }

  override fun stopEncoding() {
    if (mStopped) {
      return
    }
    mStopped = true

    val completer = Semaphore(0)
    mHandler?.post {
      mStoppedCompleter = completer
      if (mInputBufferIndex >= 0) {
        processInputBuffer()
      }
    }

    try {
      // Wait for the encoder to finish
      completer.acquire()
    } finally {
      quitSafely()
    }
  }

  private fun initEncoding() {
    calculateInputRate()

    var codec: MediaCodec? = null
    var container: IContainerWriter?

    try {
      codec = MediaCodec.createByCodecName(codecName)
      codec.setCallback(AudioRecorderCodecCallback(), Handler(looper))
      codec.configure(mediaFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
      codec.start()

      container = format.getContainer(config.path)

      mCodec = codec
      mContainer = container
    } catch (e: Exception) {
      codec?.release()
      onError(e)
    }
  }

  private fun processInputBuffer() {
    val codec = mCodec ?: return

    try {
      val s = mQueue.peekFirst()
      if (s == null) {
        // There's no more data to encode.
        if (mStoppedCompleter != null) {
          // We're done, so send EOS
          codec.queueInputBuffer(
            mInputBufferIndex, 0, 0,
            getPresentationTimestampUs(mInputBufferPosition),
            MediaCodec.BUFFER_FLAG_END_OF_STREAM
          )
          mInputBufferIndex = -1 // Reset index after sending EOS
        }
        return
      }

      val b = codec.getInputBuffer(mInputBufferIndex)!!
      val sz = min(b.capacity(), s.remaining())
      val ts = getPresentationTimestampUs(mInputBufferPosition)
      b.put(s.bytes, s.position, sz)

      codec.queueInputBuffer(mInputBufferIndex, 0, sz, ts, 0)

      mInputBufferPosition += sz.toLong()
      s.position += sz

      if (s.isConsumed()) {
        mQueue.pop()
      }

      // Reset the input buffer index
      mInputBufferIndex = -1
    } catch (e: Exception) {
      onError(e)
    }
  }

  private fun processOutputBuffer(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
    try {
      val container = mContainer

      if (container != null && info.size != 0) {
        // The CSD (Codec-specific Data) is passed to muxer in MediaFormat. So we ignore it.
        val ignoreSample = container.ignoreCodecSpecificData() && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0

        if (!ignoreSample) {
          val out = codec.getOutputBuffer(index)

          if (out != null) {
            if (container.isStream()) {
              listener.onEncoderStream(container.writeStream(mContainerTrack, out, info))
            } else {
              container.writeSampleData(mContainerTrack, out, info)
            }
          }
        }
      }

      codec.releaseOutputBuffer(index, false)

      if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
        stopAndRelease()
      }
    } catch (e: Exception) {
      onError(e)
    }
  }

  private fun onError(e: Exception) {
    mStopped = true
    stopAndRelease()
    listener.onEncoderFailure(e)
  }

  private fun stopAndRelease() {
    try {
      mCodec?.stop()
    } finally {
      mCodec?.release()
      mCodec = null
    }

    try {
      mContainer?.stop()
    } finally {
      mContainer?.release()
      mContainer = null
    }

    mStoppedCompleter?.release()
    mStoppedCompleter = null
  }

  private fun calculateInputRate() {
    val bitsPerSample = 16 // Default to 16-bit PCM
    val sampleRate = mediaFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
    val channelCount = mediaFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

    // bytes per microsecond
    mRate = (bitsPerSample / 8.0f) * sampleRate * channelCount * 1e-6f
  }

  private fun getPresentationTimestampUs(position: Long): Long {
    return (position / mRate).toLong()
  }

  internal inner class AudioRecorderCodecCallback : MediaCodec.Callback() {
    override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {
      mInputBufferIndex = index
      processInputBuffer()
    }

    override fun onOutputBufferAvailable(
      codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo
    ) {
      processOutputBuffer(codec, index, info)
    }

    override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {
      onError(e)
    }

    override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
      mContainerTrack = mContainer?.addTrack(format) ?: -1
      mContainer?.start()

      Log.d("MediaCodecEncoder", "Output format set: $format")
    }
  }

  private class Sample(val bytes: ByteArray) {
    var position: Int = 0
    fun remaining(): Int = bytes.size - position
    fun isConsumed(): Boolean = position >= bytes.size
  }
}
