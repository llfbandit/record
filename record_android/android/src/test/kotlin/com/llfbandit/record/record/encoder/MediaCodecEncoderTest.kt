package com.llfbandit.record.record.encoder

import android.media.MediaFormat
import com.llfbandit.record.record.format.Format
import com.llfbandit.record.record.model.AudioEncoder
import com.llfbandit.record.testRecordConfig
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.shadows.ShadowMediaCodec

@RunWith(RobolectricTestRunner::class)
class MediaCodecEncoderTest {
  private companion object {
    const val CODEC = MediaFormat.MIMETYPE_AUDIO_AAC
    const val CODEC_BUFFER_SIZE = 1024
    const val ADTS_HEADER_SIZE = 7
  }

  private val chunks = mutableListOf<ByteArray>()

  @Before
  fun setUp() {
    // Echoes its input, so every byte fed in must come out.
    ShadowMediaCodec.addEncoder(
      CODEC,
      ShadowMediaCodec.CodecConfig(CODEC_BUFFER_SIZE, CODEC_BUFFER_SIZE) { input, output -> output.put(input) },
    )
  }

  @After
  fun tearDown() = ShadowMediaCodec.clearCodecs()

  private fun encoder(): MediaCodecEncoder {
    val config = testRecordConfig(path = null, encoder = AudioEncoder.AacLc, numChannels = 1)
    val format = Format.selectFormat(AudioEncoder.AacLc)
    return MediaCodecEncoder(config, format, format.getMediaFormat(config), { chunks += it }, CODEC)
  }

  @Test
  fun `input larger than a codec buffer comes out whole once stopped`() {
    val encoder = encoder()
    encoder.startEncoding()

    encoder.encode(ByteArray(3 * CODEC_BUFFER_SIZE + 100) { 1 })
    assertNull(encoder.stopEncoding())

    assertTrue("the codec output reaches the container", chunks.isNotEmpty())
    assertEquals(3 * CODEC_BUFFER_SIZE + 100, chunks.sumOf { it.size - ADTS_HEADER_SIZE })
  }

  @Test
  fun `input beyond the free codec buffers waits, then comes out whole`() {
    val encoder = encoder()
    encoder.startEncoding()

    repeat(10) { encoder.encode(ByteArray(10 * CODEC_BUFFER_SIZE) { 1 }) }
    encoder.pump()
    assertNull(encoder.stopEncoding())

    assertEquals(100 * CODEC_BUFFER_SIZE, chunks.sumOf { it.size - ADTS_HEADER_SIZE })
  }

  @Test
  fun `a stop with no input still ends the stream cleanly`() {
    val encoder = encoder()
    encoder.startEncoding()

    assertNull(encoder.stopEncoding())
  }

  @Test
  fun `a stop before start does nothing`() {
    assertNull(encoder().stopEncoding())
    assertTrue(chunks.isEmpty())
  }
}
