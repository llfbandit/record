package com.llfbandit.record.record.encoder

import android.media.MediaCodec
import android.media.MediaFormat
import android.util.Log
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.container.IContainerWriter
import com.llfbandit.record.record.container.toByteArray
import com.llfbandit.record.record.format.Format
import kotlin.math.min

class MediaCodecEncoder(
  private val config: RecordConfig,
  private val format: Format,
  private val mediaFormat: MediaFormat,
  private val onChunk: (ByteArray) -> Unit,
  private val codecName: String,
) : IEncoder {
  private companion object {
    private const val TAG = "MediaCodecEncoder"
    // Only stop waits on the codec: short waits, ~2 s in a row means it is stuck.
    private const val DEQUEUE_TIMEOUT_US = 10_000L
    private const val MAX_IDLE_WAITS = 200
    // Input the codec has not taken for this long: treat it as stuck.
    private const val MAX_PENDING_SECONDS = 2L
  }

  private var codec: MediaCodec? = null
  private var container: IContainerWriter? = null
  private val info = MediaCodec.BufferInfo()
  private val bytesPerSecond = 2L *
    mediaFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE) *
    mediaFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
  private var inputPosition = 0L
  // Input waiting for a free codec buffer, so encode() never blocks the control thread.
  private val pending = ArrayDeque<ByteArray>()
  // Bytes of pending.first() already queued.
  private var pendingOffset = 0
  private var pendingBytes = 0L
  // One big chunk alone does not mean the codec is stuck.
  private var maxChunkBytes = 0L
  private var containerTrack = 0
  private var containerSetup = false
  private var pendingFormat: MediaFormat? = null
  // A failed codec can't take an end of stream, so stopEncoding() only releases it.
  private var failed = false

  override fun startEncoding() {
    val c = MediaCodec.createByCodecName(codecName)
    try {
      c.configure(mediaFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
      c.start()
      container = format.createWriter(mediaFormat, config.path, onChunk)
    } catch (e: Exception) {
      c.release()
      throw e
    }
    codec = c
  }

  override fun encode(bytes: ByteArray) {
    if (bytes.isNotEmpty()) {
      pending.addLast(bytes)
      pendingBytes += bytes.size
      maxChunkBytes = maxOf(maxChunkBytes, bytes.size.toLong())
    }
    pump()
  }

  override fun pump() {
    val c = checkNotNull(codec) { "Encoder not started." }
    try {
      while (pending.isNotEmpty()) {
        val index = c.dequeueInputBuffer(0)
        if (index < 0) break
        queuePending(c, index)
        drain(c)
      }
      drain(c)
      check(pendingBytes <= bytesPerSecond * MAX_PENDING_SECONDS + maxChunkBytes) { "Codec stopped taking input." }
    } catch (e: Exception) {
      failed = true
      throw e
    }
  }

  // Fills the buffer from as many chunks as fit: one small chunk per buffer would starve the codec.
  private fun queuePending(c: MediaCodec, index: Int) {
    val buffer = checkNotNull(c.getInputBuffer(index))
    var size = 0
    while (pending.isNotEmpty() && buffer.hasRemaining()) {
      val head = pending.first()
      val count = min(buffer.remaining(), head.size - pendingOffset)
      buffer.put(head, pendingOffset, count)
      size += count
      pendingOffset += count
      if (pendingOffset == head.size) {
        pending.removeFirst()
        pendingOffset = 0
      }
    }
    c.queueInputBuffer(index, 0, size, timestampUs(inputPosition), 0)
    inputPosition += size
    pendingBytes -= size
  }

  override fun stopEncoding(): Exception? {
    var error: Exception? = null
    val c = codec
    codec = null

    if (c != null) {
      try {
        if (!failed) endStream(c)
      } catch (e: Exception) {
        error = e
      }
      try {
        c.stop()
      } catch (e: Exception) {
        error = error ?: e
      } finally {
        c.release()
      }
    }

    try {
      container?.release()
    } catch (e: Exception) {
      error = error ?: e
    } finally {
      container = null
    }
    return error
  }

  // Waits, unlike pump(): the file must hold every pending byte before it is finalized.
  private fun endStream(c: MediaCodec) {
    var idleWaits = 0
    while (true) {
      val index = c.dequeueInputBuffer(DEQUEUE_TIMEOUT_US)
      if (index < 0) {
        check(++idleWaits < MAX_IDLE_WAITS) { "Codec stopped taking input." }
        drain(c)
        continue
      }
      idleWaits = 0
      if (pending.isEmpty()) {
        c.queueInputBuffer(index, 0, 0, timestampUs(inputPosition), MediaCodec.BUFFER_FLAG_END_OF_STREAM)
        break
      }
      queuePending(c, index)
      drain(c)
    }
    drain(c, untilEndOfStream = true)
  }

  private fun drain(c: MediaCodec, untilEndOfStream: Boolean = false) {
    var idleWaits = 0
    while (true) {
      val index = c.dequeueOutputBuffer(info, if (untilEndOfStream) DEQUEUE_TIMEOUT_US else 0)
      when {
        index == MediaCodec.INFO_TRY_AGAIN_LATER -> {
          if (!untilEndOfStream) return
          if (++idleWaits >= MAX_IDLE_WAITS) {
            Log.w(TAG, "End of stream never came out; the file may miss its last frames.")
            return
          }
        }

        index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> if (!containerSetup) {
          pendingFormat = c.outputFormat
          trySetupContainer()
        }

        index >= 0 -> {
          idleWaits = 0
          write(c, index)
          if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) return
        }
      }
    }
  }

  private fun write(c: MediaCodec, index: Int) {
    val container = checkNotNull(container)
    if (info.size != 0) {
      val out = c.getOutputBuffer(index)
      if ((info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
        container.onCsdBuffer(out?.toByteArray(info))
        trySetupContainer()
      } else if (out != null && containerSetup) {
        container.writeSampleData(containerTrack, out, info)
      }
    }
    c.releaseOutputBuffer(index, false)
  }

  private fun trySetupContainer() {
    if (containerSetup) return
    val container = container ?: return
    val format = pendingFormat ?: return
    if (!container.isReadyForSetup(format)) return

    containerSetup = true
    containerTrack = container.addTrack(format)
    container.start()
    Log.d(TAG, "Container setup done: $format")
  }

  private fun timestampUs(position: Long): Long = position * 1_000_000L / bytesPerSecond
}
