package com.llfbandit.record

import android.media.AudioDeviceInfo
import com.llfbandit.record.record.model.AudioInterruption
import com.llfbandit.record.record.model.AudioRouteChange
import com.llfbandit.record.record.model.RecordConfig

/** Builds a [RecordConfig] usable from plain JVM unit tests. A [device] needs Robolectric. */
fun testRecordConfig(
  path: String? = "/tmp/record-test.out",
  encoder: String = "wav",
  bitRate: Int = 128000,
  sampleRate: Int = 44100,
  numChannels: Int = 1,
  device: AudioDeviceInfo? = null,
  audioInterruption: Int = AudioInterruption.PAUSE.ordinal,
  audioRouteChange: Int = AudioRouteChange.PAUSE.ordinal,
  streamBufferSize: Int? = null,
): RecordConfig = RecordConfig(
  path = path,
  encoder = encoder,
  bitRate = bitRate,
  sampleRate = sampleRate,
  numChannels = numChannels,
  device = device,
  audioSource = 0,
  audioManagerMode = 0,
  audioInterruption = audioInterruption,
  audioRouteChange = audioRouteChange,
  streamBufferSize = streamBufferSize,
)
