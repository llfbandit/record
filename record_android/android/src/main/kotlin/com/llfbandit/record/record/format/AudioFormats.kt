package com.llfbandit.record.record.format

import android.media.MediaCodecList
import android.media.MediaFormat
import com.llfbandit.record.record.AudioEncoder

object AudioFormats {
  fun isEncoderSupported(mimeType: String?): Boolean {
    if (mimeType == null) {
      return false
    }
    if (mimeType == MediaFormat.MIMETYPE_AUDIO_RAW) {
      return true
    }

    val mcl = MediaCodecList(MediaCodecList.REGULAR_CODECS)
    for (info in mcl.codecInfos) {
      if (info.isEncoder) {
        for (supportedType in info.supportedTypes) {
          if (supportedType.equals(mimeType, ignoreCase = true)) {
            return true
          }
        }
      }
    }
    return false
  }

  fun getMimeType(encoder: String?): String? {
    return when (encoder) {
      AudioEncoder.AacLc.value, AudioEncoder.AacEld.value, AudioEncoder.AacHe.value -> MediaFormat.MIMETYPE_AUDIO_AAC
      AudioEncoder.AmrNb.value -> MediaFormat.MIMETYPE_AUDIO_AMR_NB
      AudioEncoder.AmrWb.value -> MediaFormat.MIMETYPE_AUDIO_AMR_WB
      AudioEncoder.Wav.value, AudioEncoder.Pcm16bits.value -> MediaFormat.MIMETYPE_AUDIO_RAW
      AudioEncoder.Opus.value -> MediaFormat.MIMETYPE_AUDIO_OPUS
      AudioEncoder.Flac.value -> MediaFormat.MIMETYPE_AUDIO_FLAC
      else -> null
    }
  }
}