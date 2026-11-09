package com.llfbandit.record.record.recorder

import com.llfbandit.record.record.recorder.engine.DEFAULT_AMPLITUDE_DB
import com.llfbandit.record.record.recorder.engine.peakToDb
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs

/** Holds the 16-bit samples a capture reads. */
class PcmBuffer(sizeInBytes: Int) {
  /** The reader fills it in place. */
  val samples = ShortArray(sizeInBytes / 2)

  /** Little-endian bytes of the first [count] samples. */
  fun toByteArray(count: Int = samples.size): ByteArray {
    val bytes = ByteBuffer.allocate(count * 2).order(ByteOrder.LITTLE_ENDIAN)
    bytes.asShortBuffer().put(samples, 0, count)
    return bytes.array()
  }

  /** Peak level of the samples in dB, or [DEFAULT_AMPLITUDE_DB] when they are all zero. */
  fun amplitudeDb(): Double = peakToDb(samples.maxOf { abs(it.toInt()) })
}
