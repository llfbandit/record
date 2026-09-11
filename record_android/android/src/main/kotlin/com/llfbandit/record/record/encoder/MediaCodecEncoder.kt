package com.llfbandit.record.record.encoder

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.container.IContainerWriter
import com.llfbandit.record.record.format.Format
import java.util.LinkedList
import java.util.concurrent.atomic.AtomicReference
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
  private var mContainerSetup = false
  private var mPendingFormat: MediaFormat? = null

  // Claimed atomically, so the last thread out answers stopEncoding() exactly once.
  private val mOnStopped = AtomicReference<((Exception?) -> Unit)?>(null)
  @Volatile private var mStopped = false

  // First failure seen on the codec thread.
  private var mError: Exception? = null

  override fun encode(bytes: ByteArray) {
    if (mStopped) {
      return
    }

    val s = Sample(bytes)
    mHandler?.post {
      mQueue.add(s)
      if (mInputBufferIndex >= 0) {
        processInputBuffer()
      }
    }
  }

  override fun startEncoding() {
    start() // Start the thread
    mHandler = Handler(looper)
    mHandler?.post { initEncoding() }
  }

  override fun stopEncoding(done: (Exception?) -> Unit) {
    if (mStopped) {
      // Already torn down by onError(): still surface what went wrong.
      done(mError)
      return
    }
    mStopped = true

    // Never started: nothing to drain or release.
    val handler = mHandler
    if (handler == null) {
      done(null)
      return
    }
    mOnStopped.set(done)

    // A codec that is already gone cannot drain an EOS.
    val posted = handler.post {
      if (mCodec == null) {
        finishStop()
      } else if (mInputBufferIndex >= 0) {
        processInputBuffer()
      }
    }
    // The looper already quit (onError() won the race): nothing on it will answer.
    if (!posted) finishStop()
  }

  // The EOS drained, or never will: let the thread go.
  private fun finishStop() {
    val done = mOnStopped.getAndSet(null) ?: return // Nobody waiting: onError() quits.
    quitSafely()
    done(mError)
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

      container = format.createWriter(mediaFormat, config.path)

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
        if (mOnStopped.get() != null) {
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
        val isCsd = (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0

        if (isCsd) {
          onCsdBuffer(codec, index, info, container)
        } else {
          val out = codec.getOutputBuffer(index)

          if (out != null && mContainerSetup) {
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

  private fun onCsdBuffer(
    codec: MediaCodec,
    index: Int,
    info: MediaCodec.BufferInfo,
    container: IContainerWriter
  ) {
    val csd = codec.getOutputBuffer(index)?.let { out ->
      out.position(info.offset)
      out.limit(info.offset + info.size)
      ByteArray(info.size).also { out.get(it) }
    }
    container.onCsdBuffer(csd)
    trySetupContainer()
  }

  private fun trySetupContainer() {
    if (mContainerSetup) return
    val container = mContainer ?: return
    val format = mPendingFormat ?: return
    if (!container.isReadyForSetup(format)) return

    mContainerSetup = true
    mContainerTrack = container.addTrack(format)
    container.start()
    Log.d("MediaCodecEncoder", "Container setup done: $format")
  }

  private fun onError(e: Exception) {
    // Before the flag: a reader that sees mStopped must also see why.
    saveError(e)
    mStopped = true
    stopAndRelease()
    listener.onEncoderFailure(e)
    quitSafely()
  }

  private fun saveError(e: Exception) {
    if (mError == null) mError = e
  }

  // Never throws: a teardown error is noted, and stopEncoding() answered last.
  private fun stopAndRelease() {
    try {
      try {
        mCodec?.stop()
      } catch (e: Exception) {
        saveError(e)
      } finally {
        mCodec?.release()
        mCodec = null
      }

      try {
        mContainer?.release()
      } catch (e: Exception) {
        saveError(e)
      } finally {
        mContainer = null
      }
    } finally {
      finishStop()
    }
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
      if (mContainerSetup) return

      mPendingFormat = format
      trySetupContainer()
    }
  }

  private class Sample(val bytes: ByteArray) {
    var position: Int = 0
    fun remaining(): Int = bytes.size - position
    fun isConsumed(): Boolean = position >= bytes.size
  }
}
