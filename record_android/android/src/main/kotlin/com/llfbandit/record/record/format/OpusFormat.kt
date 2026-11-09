package com.llfbandit.record.record.format

import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaRecorder
import android.os.Build
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.container.IContainerWriter
import com.llfbandit.record.record.container.MuxerContainer

class OpusFormat : Format() {
  private val sampleRates = intArrayOf(
    8000, 12000, 16000, 24000, 48000
  )

  override val mimeTypeAudio: String = MediaFormat.MIMETYPE_AUDIO_OPUS

  override fun getMediaFormat(config: RecordConfig): MediaFormat {
    return MediaFormat.createAudioFormat(mimeTypeAudio, nearestValue(sampleRates, config.sampleRate), config.numChannels).apply {
      setInteger(MediaFormat.KEY_BIT_RATE, config.bitRate)
    }
  }

  // No Opus in MediaRecorder below API 29; keep recording AAC.
  override fun legacyRecorder(config: RecordConfig) =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      LegacyRecorder(MediaRecorder.OutputFormat.OGG, MediaRecorder.AudioEncoder.OPUS)
    } else {
      LegacyRecorder(MediaRecorder.OutputFormat.MPEG_4, MediaRecorder.AudioEncoder.AAC)
    }

  override fun createWriter(
    mediaFormat: MediaFormat,
    path: String?,
    onChunk: (ByteArray) -> Unit,
  ): IContainerWriter {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
      throw IllegalAccessException("Opus requires min API version: " + Build.VERSION_CODES.Q)
    }

    return MuxerContainer(requirePath(path), false, MediaMuxer.OutputFormat.MUXER_OUTPUT_OGG)
  }
}