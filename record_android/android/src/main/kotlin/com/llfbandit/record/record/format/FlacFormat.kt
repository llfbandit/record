package com.llfbandit.record.record.format

import android.media.MediaFormat
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.container.FlacContainer
import com.llfbandit.record.record.container.IContainerWriter

class FlacFormat : Format() {
  private val sampleRates = intArrayOf(
    8000, 11025, 22050, 44100, 48000
  )

  override val mimeTypeAudio: String = MediaFormat.MIMETYPE_AUDIO_FLAC

  override fun getMediaFormat(config: RecordConfig): MediaFormat {
    return MediaFormat.createAudioFormat(mimeTypeAudio, nearestValue(sampleRates, config.sampleRate), config.numChannels).apply {

      // Specifics
      setInteger(MediaFormat.KEY_BIT_RATE, 0)
      setInteger(MediaFormat.KEY_FLAC_COMPRESSION_LEVEL, 8)
    }
  }

  override fun createWriter(
    mediaFormat: MediaFormat,
    path: String?,
    onChunk: (ByteArray) -> Unit,
  ): IContainerWriter {
    if (path == null) {
      throw IllegalArgumentException("Path not provided. Stream is not supported.")
    }

    return FlacContainer(path)
  }
}