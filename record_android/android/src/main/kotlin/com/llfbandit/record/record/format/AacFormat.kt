package com.llfbandit.record.record.format

import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
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

      // Specifics
      @Suppress("CascadeIf")
      if (config.encoder == AudioEncoder.AacLc) {
        setInteger(
          MediaFormat.KEY_AAC_PROFILE,
          MediaCodecInfo.CodecProfileLevel.AACObjectLC
        )
      } else if (config.encoder == AudioEncoder.AacEld) {
        setInteger(
          MediaFormat.KEY_AAC_PROFILE,
          MediaCodecInfo.CodecProfileLevel.AACObjectELD
        )
      } else if (config.encoder == AudioEncoder.AacHe) {
        setInteger(
          MediaFormat.KEY_AAC_PROFILE,
          MediaCodecInfo.CodecProfileLevel.AACObjectHE
        )
      }
    }
  }

  override fun createWriter(
    mediaFormat: MediaFormat,
    path: String?,
    onChunk: (ByteArray) -> Unit,
  ): IContainerWriter {
    if (path == null) {
      val aacProfile = mediaFormat.getInteger(MediaFormat.KEY_AAC_PROFILE)
      if (aacProfile != MediaCodecInfo.CodecProfileLevel.AACObjectLC) {
        throw IllegalArgumentException("Stream is not supported.")
      }

      return AdtsContainer(
        mediaFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE),
        mediaFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT),
        aacProfile,
        onChunk,
      )
    }

    return MuxerContainer(path, true, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
  }
}