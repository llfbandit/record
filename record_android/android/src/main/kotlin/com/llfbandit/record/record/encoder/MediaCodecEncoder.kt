package com.llfbandit.record.record.encoder

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Handler
import android.os.HandlerThread
import android.os.Message
import android.util.Log
import com.llfbandit.record.record.RecordConfig
import com.llfbandit.record.record.container.IContainerWriter
import com.llfbandit.record.record.format.Format
import java.util.LinkedList
import java.util.concurrent.Semaphore
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.min

class MediaCodecEncoder(
    private val config: RecordConfig,
    private val format: Format,
    private val mediaFormat: MediaFormat,
    private val listener: EncoderListener,
    private val codec: String,
) : IEncoder,
    HandlerThread("MediaCodecEncoder Thread"),
    Handler.Callback {
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
    private var mStopped = AtomicBoolean(false)

    override fun encode(bytes: ByteArray) {
        if (mStopped.get()) {
            return
        }

        val s = Sample()
        s.bytes = bytes
        mHandler?.obtainMessage(MSG_ENCODE_INPUT, s)?.sendToTarget()
    }

    override fun startEncoding() {
        start() // Start the thread

        mHandler = Handler(looper, this)
        mHandler?.obtainMessage(MSG_INIT)?.sendToTarget()
    }

    override fun stopEncoding() {
        if (mStopped.get()) {
            return
        }
        mStopped.set(true)

        val completer = Semaphore(0)
        mHandler?.obtainMessage(MSG_STOP, completer)?.sendToTarget()

        try {
            // Wait for the encoder to finish
            completer.acquire()
        } finally {
            quitSafely()
        }
    }

    override fun handleMessage(msg: Message): Boolean {
        if (msg.what == MSG_INIT) {
            initEncoding()
        } else if (msg.what == MSG_STOP) {
            mStoppedCompleter = msg.obj as Semaphore
            if (mInputBufferIndex >= 0) {
                processInputBuffer()
            }
        } else if (msg.what == MSG_ENCODE_INPUT) {
            if (!mStopped.get()) {
                mQueue.addLast(msg.obj as Sample)
                if (mInputBufferIndex >= 0) {
                    processInputBuffer()
                }
            }
        }

        return true
    }

    private fun initEncoding() {
        calculateInputRate()

        try {
            mCodec = MediaCodec.createByCodecName(codec)
            mCodec?.setCallback(AudioRecorderCodecCallback(), Handler(looper))
            mCodec?.configure(mediaFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            mCodec?.start()
        } catch (e: Exception) {
            mCodec?.release()
            mCodec = null
            onError(e)
            return
        }

        try {
            mContainer = format.getContainer(config.path)
        } catch (e: Exception) {
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
            val sz = min(b.capacity().toDouble(), (s.bytes.size - s.offset).toDouble()).toInt()
            val ts = getPresentationTimestampUs(mInputBufferPosition)
            b.put(s.bytes, s.offset, sz)

            codec.queueInputBuffer(mInputBufferIndex, 0, sz, ts, 0)

            mInputBufferPosition += sz.toLong()
            s.offset += sz

            // Are we done with this sample?
            if (s.offset >= s.bytes.size) {
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
            val outputBuffer = codec.getOutputBuffer(index)
            if (outputBuffer != null) {
                mContainer?.writeSampleData(mContainerTrack, outputBuffer, info)
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
        mStopped.set(true)
        stopAndRelease()
        listener.onEncoderFailure(e)
    }

    private fun stopAndRelease() {
        mCodec?.stop()
        mCodec?.release()
        mCodec = null

        mContainer?.stop()
        mContainer?.release()
        mContainer = null

        mStoppedCompleter?.release()
        mStoppedCompleter = null
    }

    private fun calculateInputRate() {
        mRate = 16.toFloat()
        mRate *= mediaFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE).toFloat()
        mRate *= mediaFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT).toFloat()
        mRate *= 1e-6.toFloat() // -> us
        mRate /= 8f // -> bytes
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
            codec: MediaCodec,
            index: Int,
            info: MediaCodec.BufferInfo
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

    private inner class Sample {
        lateinit var bytes: ByteArray
        var offset: Int = 0
    }

    companion object {
        private const val MSG_INIT = 100
        private const val MSG_ENCODE_INPUT = 101
        private const val MSG_STOP = 999
    }
}
