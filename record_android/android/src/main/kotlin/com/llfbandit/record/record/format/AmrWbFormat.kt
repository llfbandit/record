package com.llfbandit.record.record.format

import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.container.IContainerWriter
import com.llfbandit.record.record.container.MuxerContainer

class AmrWbFormat : Format() {
  private val bitRates = intArrayOf(
    6600, 8850, 12650, 14250, 15850, 18250, 19850, 23050, 23850
  )

  override val mimeTypeAudio: String = MediaFormat.MIMETYPE_AUDIO_AMR_WB

  override fun getMediaFormat(config: RecordConfig): MediaFormat {
    // The SDK requires this sample rate, in mono.
    return MediaFormat.createAudioFormat(mimeTypeAudio, 16000, 1).apply {
      setInteger(MediaFormat.KEY_BIT_RATE, nearestValue(bitRates, config.bitRate))
    }
  }

  override fun createWriter(mediaFormat: MediaFormat, path: String?): IContainerWriter {
    if (path == null) {
      throw IllegalArgumentException("Path not provided. Stream is not supported.")
    }
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      throw IllegalAccessException("AmrWb requires min API version: " + Build.VERSION_CODES.O)
    }

    return MuxerContainer(path, false, MediaMuxer.OutputFormat.MUXER_OUTPUT_3GPP)
  }
}