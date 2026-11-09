package com.llfbandit.record.record.recorder

import com.llfbandit.record.record.recorder.engine.DEFAULT_AMPLITUDE_DB
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Checks PcmBuffer conversions without any device. */
class PcmBufferTest {
  private fun buffer(vararg values: Int) = PcmBuffer(sizeInBytes = values.size * 2).apply {
    values.forEachIndexed { i, v -> samples[i] = v.toShort() }
  }

  // --- amplitude ---

  @Test
  fun `silence reports the floor rather than negative infinity`() {
    assertEquals(DEFAULT_AMPLITUDE_DB, buffer(0, 0, 0, 0).amplitudeDb(), 0.0)
  }

  @Test
  fun `a full scale sample reports 0 dB`() {
    assertEquals(0.0, buffer(32767).amplitudeDb(), 0.0001)
  }

  @Test
  fun `half scale reports about -6 dB`() {
    assertEquals(-6.02, buffer(16384).amplitudeDb(), 0.01)
  }

  @Test
  fun `the most negative sample never reports above 0 dB`() {
    // Short.MIN_VALUE is one louder than full scale, which log10 would put above 0.
    assertTrue(buffer(Short.MIN_VALUE.toInt()).amplitudeDb() <= 0.0)
  }

  @Test
  fun `the peak is taken regardless of sign or position`() {
    assertEquals(buffer(20000).amplitudeDb(), buffer(1, -20000, 300, 0).amplitudeDb(), 0.0)
  }

  // --- bytes ---

  @Test
  fun `samples are written little endian`() {
    assertArrayEquals(byteArrayOf(0x02, 0x01), buffer(0x0102).toByteArray())
  }

  @Test
  fun `every sample is emitted`() {
    assertEquals(8, buffer(1, 2, 3, 4).toByteArray().size)
  }

  @Test
  fun `a count emits only the first samples`() {
    assertArrayEquals(byteArrayOf(1, 0, 2, 0), buffer(1, 2, 3).toByteArray(2))
  }

  @Test
  fun `negative samples keep their two's complement bytes`() {
    assertArrayEquals(byteArrayOf(-1, -1), buffer(-1).toByteArray())
  }
}
