package com.llfbandit.record.record.format

import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import com.llfbandit.record.record.RecordConfig
import com.llfbandit.record.record.container.IContainerWriter
import com.llfbandit.record.record.container.MuxerContainer

class AmrWbFormat  : Format() {
    private val bitRates = intArrayOf(
        6600, 8850, 12650, 14250, 15850, 18250, 19850, 23050, 23850
    )

    override val mimeTypeAudio: String = MediaFormat.MIMETYPE_AUDIO_AMR_WB
    override val passthrough: Boolean = false

    override fun getMediaFormat(config: RecordConfig): MediaFormat {
        val format = MediaFormat().apply {
            setString(MediaFormat.KEY_MIME, mimeTypeAudio)
            setInteger(MediaFormat.KEY_SAMPLE_RATE, 16000) // required by SDK
            setInteger(MediaFormat.KEY_CHANNEL_COUNT, 1)
            setInteger(MediaFormat.KEY_BIT_RATE, nearestValue(bitRates, config.bitRate))
        }

        return format
    }

    override fun getContainer(path: String?): IContainerWriter {
        if (path == null) {
            throw IllegalArgumentException("Path not provided. Stream is not supported.")
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            throw IllegalAccessException("AmrWb requires min API version: " + Build.VERSION_CODES.O)
        }

        return MuxerContainer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_3GPP)
    }
}