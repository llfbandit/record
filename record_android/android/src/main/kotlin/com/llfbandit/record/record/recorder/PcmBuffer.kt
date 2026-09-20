package com.llfbandit.record.record.recorder

import com.llfbandit.record.record.recorder.engine.DEFAULT_AMPLITUDE_DB
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.log10

/** Holds the 16-bit samples a capture reads. */
class PcmBuffer(sizeInBytes: Int) {
  private companion object {
    const val MAX_PCM_VALUE = 32767.0 // 2^15 - 1 for 16-bit signed
  }

  /** The reader fills it in place; only the first `count` values of a read are valid. */
  val samples = ShortArray(sizeInBytes / 2)

  /** Little-endian bytes of the first [count] samples. */
  fun toByteArray(count: Int): ByteArray {
    val bytes = ByteBuffer.allocate(count * 2).order(ByteOrder.LITTLE_ENDIAN)
    bytes.asShortBuffer().put(samples, 0, count)
    return bytes.array()
  }

  /** Peak level of the first [count] samples in dB, or [DEFAULT_AMPLITUDE_DB] when they are all zero. */
  fun amplitudeDb(count: Int): Double {
    var peak = 0
    for (i in 0 until count) {
      val value = abs(samples[i].toInt())
      if (value > peak) peak = value
    }
    if (peak == 0) return DEFAULT_AMPLITUDE_DB

    // Short.MIN_VALUE has no matching positive value, so this could go slightly above 0 dB.
    return 0.0.coerceAtMost(20 * log10(peak / MAX_PCM_VALUE))
  }
}
