package com.llfbandit.record.record.format

import android.media.MediaCodecList
import android.media.MediaFormat

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
            "aacLc", "aacEld", "aacHe" -> MediaFormat.MIMETYPE_AUDIO_AAC
            "amrNb" -> MediaFormat.MIMETYPE_AUDIO_AMR_NB
            "amrWb" -> MediaFormat.MIMETYPE_AUDIO_AMR_WB
            "wav", "pcm16bit", "pcm8bit" -> MediaFormat.MIMETYPE_AUDIO_RAW
            "opus" -> MediaFormat.MIMETYPE_AUDIO_OPUS
            "flac" -> MediaFormat.MIMETYPE_AUDIO_FLAC
            else -> null
        }
    }
}