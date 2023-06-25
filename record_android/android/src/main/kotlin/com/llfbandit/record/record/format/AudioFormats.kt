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
            AudioEncoder.aacLc, AudioEncoder.aacEld, AudioEncoder.aacHe -> MediaFormat.MIMETYPE_AUDIO_AAC
            AudioEncoder.amrNb -> MediaFormat.MIMETYPE_AUDIO_AMR_NB
            AudioEncoder.amrWb -> MediaFormat.MIMETYPE_AUDIO_AMR_WB
            AudioEncoder.wav, AudioEncoder.pcm16bits -> MediaFormat.MIMETYPE_AUDIO_RAW
            AudioEncoder.opus -> MediaFormat.MIMETYPE_AUDIO_OPUS
            AudioEncoder.flac -> MediaFormat.MIMETYPE_AUDIO_FLAC
            else -> null
        }
    }
}