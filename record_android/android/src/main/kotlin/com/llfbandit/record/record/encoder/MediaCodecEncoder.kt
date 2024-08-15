package com.llfbandit.record.record.encoder

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Handler
import android.os.HandlerThread
import android.os.Message
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
    codec: String,
) : IEncoder,
    HandlerThread("MediaCodecEncoder Thread"),
    Handler.Callback {
    private lateinit var mHandler: Handler
    private val mCodec: MediaCodec = MediaCodec.createByCodecName(codec)
    private val mQueue = LinkedList<Sample>()
    private var mRate = 0f // bytes per us
    private var mInputBufferPosition: Long = 0
    private var mInputBufferIndex = -1
    private lateinit var mContainer: IContainerWriter
    private var mContainerTrack = 0

    // Semaphore to signal the end of encoding
    private var mFinishedCompleter: Semaphore? = null
    private var mFinished = AtomicBoolean(false)
    private var mReleased = AtomicBoolean(false)

    override fun encode(bytes: ByteArray) {
        if (mFinished.get()) {
            return
        }

        val s = Sample()
        s.bytes = bytes
        mHandler.obtainMessage(MSG_ENCODE_INPUT, s).sendToTarget()
    }

    override fun startEncoding() {
        start() // Start the thread

        mHandler = Handler(looper, this)
        mHandler.obtainMessage(MSG_INIT).sendToTarget()
    }

    override fun stopEncoding() {
        if (mFinished.get()) {
            return
        }

        mFinished.set(true)
        val completer = Semaphore(0)
        mHandler.obtainMessage(MSG_STOP, completer).sendToTarget()

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
            mFinishedCompleter = msg.obj as Semaphore
            if (mInputBufferIndex >= 0) {
                processInputBuffer()
            }
        } else if (msg.what == MSG_ENCODE_INPUT) {
            mQueue.addLast(msg.obj as Sample)
            if (mInputBufferIndex >= 0) {
                processInputBuffer()
            }
        }

        return true
    }

    private fun initEncoding() {
        try {
            calculateInputRate()

            mCodec.setCallback(AudioRecorderCodecCallback(), Handler(looper))
            mCodec.configure(mediaFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            mCodec.start()

            mContainer = format.getContainer(config.path)
            mContainerTrack = mContainer.addTrack(mCodec.outputFormat)
            mContainer.start()
        } catch (e: Exception) {
            onError(e)
        }
    }

    private fun processInputBuffer() {
        try {
            val s = mQueue.peekFirst()
            if (s == null) {
                // There's no more data to encode.
                if (mFinishedCompleter != null) {
                    // We're done, so send EOS
                    mCodec.queueInputBuffer(
                        mInputBufferIndex, 0, 0,
                        getPresentationTimestampUs(mInputBufferPosition),
                        MediaCodec.BUFFER_FLAG_END_OF_STREAM
                    )
                }
                return
            }

            val b = mCodec.getInputBuffer(mInputBufferIndex)!!
            val sz = min(b.capacity().toDouble(), (s.bytes.size - s.offset).toDouble()).toInt()
            val ts = getPresentationTimestampUs(mInputBufferPosition)

            b.put(s.bytes, s.offset, sz)
            mCodec.queueInputBuffer(mInputBufferIndex, 0, sz, ts, 0)

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

    private fun processOutputBuffer(index: Int, info: MediaCodec.BufferInfo) {
        try {
            val outputBuffer = mCodec.getOutputBuffer(index)!!

            mContainer.writeSampleData(mContainerTrack, outputBuffer, info)

            mCodec.releaseOutputBuffer(index, false)

            if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                finish()
            }
        } catch (e: Exception) {
            onError(e)
        }
    }

    private fun onError(e: Exception) {
        mFinished.set(true)
        stopAndRelease()
        listener.onEncoderFailure(e)
    }

    private fun finish() {
        stopAndRelease()
        mFinishedCompleter?.release()
    }

    private fun stopAndRelease() {
        if (mReleased.get()) {
            return
        }
        mReleased.set(true)

        mCodec.stop()
        mCodec.release()

        mContainer.stop()
        mContainer.release()
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
            processOutputBuffer(index, info)
        }

        override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {
            onError(e)
        }

        override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
            // Do nothing. Format will never change as we set output format from codec.
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
