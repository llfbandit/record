package com.llfbandit.record.record.format

import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaRecorder
import com.llfbandit.record.record.model.AudioEncoder
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.container.AdtsContainer
import com.llfbandit.record.record.container.IContainerWriter
import com.llfbandit.record.record.container.MuxerContainer

class AacFormat : Format() {
  override val mimeTypeAudio: String = MediaFormat.MIMETYPE_AUDIO_AAC

  override fun supportsStream(config: RecordConfig): Boolean = config.encoder == AudioEncoder.AacLc

  override fun getMediaFormat(config: RecordConfig): MediaFormat {
    return MediaFormat.createAudioFormat(mimeTypeAudio, config.sampleRate, config.numChannels).apply {
      setInteger(MediaFormat.KEY_BIT_RATE, config.bitRate)
      setInteger(
        MediaFormat.KEY_AAC_PROFILE,
        when (config.encoder) {
          AudioEncoder.AacEld -> MediaCodecInfo.CodecProfileLevel.AACObjectELD
          AudioEncoder.AacHe -> MediaCodecInfo.CodecProfileLevel.AACObjectHE
          else -> MediaCodecInfo.CodecProfileLevel.AACObjectLC
        }
      )
    }
  }

  override fun legacyRecorder(config: RecordConfig) = LegacyRecorder(
    MediaRecorder.OutputFormat.MPEG_4,
    when (config.encoder) {
      AudioEncoder.AacEld -> MediaRecorder.AudioEncoder.AAC_ELD
      AudioEncoder.AacHe -> MediaRecorder.AudioEncoder.HE_AAC
      else -> MediaRecorder.AudioEncoder.AAC
    },
  )

  override fun createWriter(
    mediaFormat: MediaFormat,
    path: String?,
    onChunk: (ByteArray) -> Unit,
  ): IContainerWriter {
    if (path == null) {
      return AdtsContainer(
        mediaFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE),
        mediaFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT),
        mediaFormat.getInteger(MediaFormat.KEY_AAC_PROFILE),
        onChunk,
      )
    }

    return MuxerContainer(path, true, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
  }
}