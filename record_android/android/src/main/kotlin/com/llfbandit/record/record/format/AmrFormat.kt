package com.llfbandit.record.record.format

import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaRecorder
import android.os.Build
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.container.IContainerWriter
import com.llfbandit.record.record.container.MuxerContainer

class AmrFormat private constructor(
  override val mimeTypeAudio: String,
  private val sampleRate: Int,
  private val bitRates: IntArray,
  private val legacyEncoder: Int,
) : Format() {
  companion object {
    fun narrowBand() = AmrFormat(
      MediaFormat.MIMETYPE_AUDIO_AMR_NB, 8000,
      intArrayOf(4750, 5150, 5900, 6700, 7400, 7950, 10200, 12200),
      MediaRecorder.AudioEncoder.AMR_NB,
    )

    fun wideBand() = AmrFormat(
      MediaFormat.MIMETYPE_AUDIO_AMR_WB, 16000,
      intArrayOf(6600, 8850, 12650, 14250, 15850, 18250, 19850, 23050, 23850),
      MediaRecorder.AudioEncoder.AMR_WB,
    )
  }

  override fun legacyRecorder(config: RecordConfig) =
    LegacyRecorder(MediaRecorder.OutputFormat.THREE_GPP, legacyEncoder)

  override fun getMediaFormat(config: RecordConfig): MediaFormat {
    // The SDK requires this sample rate, in mono.
    return MediaFormat.createAudioFormat(mimeTypeAudio, sampleRate, 1).apply {
      setInteger(MediaFormat.KEY_BIT_RATE, nearestValue(bitRates, config.bitRate))
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
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      throw IllegalAccessException("AMR requires min API version: " + Build.VERSION_CODES.O)
    }

    return MuxerContainer(path, false, MediaMuxer.OutputFormat.MUXER_OUTPUT_3GPP)
  }
}
