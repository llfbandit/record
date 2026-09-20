package com.llfbandit.record.record.recorder

import com.llfbandit.record.record.recorder.engine.DEFAULT_AMPLITUDE_DB
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Checks PcmBuffer conversions without any device. */
class PcmBufferTest {
  private val buffer = PcmBuffer(sizeInBytes = 8)  // 4 samples

  private fun fill(vararg values: Int) {
    values.forEachIndexed { i, v -> buffer.samples[i] = v.toShort() }
  }

  // --- amplitude ---

  @Test
  fun `silence reports the floor rather than negative infinity`() {
    fill(0, 0, 0, 0)
    assertEquals(DEFAULT_AMPLITUDE_DB, buffer.amplitudeDb(4), 0.0)
  }

  @Test
  fun `an empty read reports the floor`() {
    fill(32767, 0, 0, 0)
    assertEquals(DEFAULT_AMPLITUDE_DB, buffer.amplitudeDb(0), 0.0)
  }

  @Test
  fun `a full scale sample reports 0 dB`() {
    fill(32767, 0, 0, 0)
    assertEquals(0.0, buffer.amplitudeDb(1), 0.0001)
  }

  @Test
  fun `half scale reports about -6 dB`() {
    fill(16384, 0, 0, 0)
    assertEquals(-6.02, buffer.amplitudeDb(1), 0.01)
  }

  @Test
  fun `the most negative sample never reports above 0 dB`() {
    // Short.MIN_VALUE is one louder than full scale, which log10 would put above 0.
    fill(Short.MIN_VALUE.toInt(), 0, 0, 0)
    assertTrue(buffer.amplitudeDb(1) <= 0.0)
  }

  @Test
  fun `the peak is taken regardless of sign or position`() {
    fill(1, -20000, 300, 0)
    assertEquals(buffer.amplitudeDb(4), buffer.amplitudeDb(2), 0.0)
  }

  @Test
  fun `samples past the read are ignored`() {
    // A short read leaves the previous, louder content in the tail of the buffer.
    fill(100, 32767, 32767, 32767)
    assertTrue("a quiet read must not report the stale tail", buffer.amplitudeDb(1) < -40.0)
  }

  // --- bytes ---

  @Test
  fun `samples are written little endian`() {
    fill(0x0102, 0, 0, 0)
    assertArrayEquals(byteArrayOf(0x02, 0x01), buffer.toByteArray(1))
  }

  @Test
  fun `only the samples that were read are emitted`() {
    fill(1, 2, 3, 4)
    assertEquals(4, buffer.toByteArray(2).size)
  }

  @Test
  fun `an empty read emits nothing`() {
    fill(1, 2, 3, 4)
    assertEquals(0, buffer.toByteArray(0).size)
  }

  @Test
  fun `negative samples keep their two's complement bytes`() {
    fill(-1, 0, 0, 0)
    assertArrayEquals(byteArrayOf(-1, -1), buffer.toByteArray(1))
  }
}
