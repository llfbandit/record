package com.llfbandit.record.record.format

import android.media.MediaCodecList
import android.media.MediaFormat
import com.llfbandit.record.record.model.AudioEncoder

object AudioFormats {
  // Listing codecs is slow and the result never changes.
  private val encoderMimeTypes: Set<String> by lazy {
    MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
      .filter { it.isEncoder }
      .flatMap { it.supportedTypes.map(String::lowercase) }
      .toSet()
  }

  fun isEncoderSupported(encoder: String?): Boolean {
    val audioEncoder = AudioEncoder.fromOrNull(encoder) ?: return false
    val mimeType = Format.selectFormat(audioEncoder).mimeTypeAudio

    return mimeType == MediaFormat.MIMETYPE_AUDIO_RAW || mimeType.lowercase() in encoderMimeTypes
  }
}
