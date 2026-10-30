package com.llfbandit.record.record.format

import android.media.MediaFormat
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.container.IContainerWriter
import com.llfbandit.record.record.container.WaveContainer

class WaveFormat : Format() {
  override val mimeTypeAudio: String = MediaFormat.MIMETYPE_AUDIO_RAW

  override fun getMediaFormat(config: RecordConfig): MediaFormat {
    val frameSize = config.numChannels * 16 / 8

    return MediaFormat.createAudioFormat(mimeTypeAudio, config.sampleRate, config.numChannels).apply {
      setInteger(KEY_X_FRAME_SIZE_IN_BYTES, frameSize)
    }
  }

  override fun createWriter(mediaFormat: MediaFormat, path: String?): IContainerWriter {
    if (path == null) {
      throw IllegalArgumentException("Path not provided. Stream is not supported.")
    }

    return WaveContainer(path, mediaFormat.getInteger(KEY_X_FRAME_SIZE_IN_BYTES))
  }
}