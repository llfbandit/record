package com.llfbandit.record

import com.llfbandit.record.record.model.AudioInterruption
import com.llfbandit.record.record.model.RecordConfig

/** Builds a [RecordConfig] usable from plain JVM unit tests. */
fun testRecordConfig(
  path: String? = "/tmp/record-test.out",
  encoder: String = "wav",
  bitRate: Int = 128000,
  sampleRate: Int = 44100,
  numChannels: Int = 1,
  audioInterruption: Int = AudioInterruption.PAUSE.ordinal,
  streamBufferSize: Int? = null,
): RecordConfig = RecordConfig(
  path = path,
  encoder = encoder,
  bitRate = bitRate,
  sampleRate = sampleRate,
  numChannels = numChannels,
  device = null,
  audioSource = 0,
  audioManagerMode = 0,
  audioInterruption = audioInterruption,
  streamBufferSize = streamBufferSize,
)
