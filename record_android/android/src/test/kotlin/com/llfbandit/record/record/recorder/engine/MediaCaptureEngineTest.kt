package com.llfbandit.record.record.recorder.engine

import android.os.Handler
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.llfbandit.record.record.model.AudioEncoder
import com.llfbandit.record.testRecordConfig
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class MediaCaptureEngineTest {
  private fun engine(encoder: AudioEncoder) = MediaCaptureEngine(
    ApplicationProvider.getApplicationContext(),
    testRecordConfig(encoder = encoder),
    { _, _ -> },
    { AutoCloseable {} },
    Handler(Looper.getMainLooper()),
    { true },
  )

  @Test
  fun `formats MediaRecorder cannot write are refused`() {
    for (encoder in listOf(AudioEncoder.Flac, AudioEncoder.Pcm16bits, AudioEncoder.Wav)) {
      assertThrows(encoder.value, IllegalArgumentException::class.java) { engine(encoder).start() }
    }
  }
}
