package com.llfbandit.record.record.format

import android.media.MediaFormat
import com.llfbandit.record.record.RecordConfig
import com.llfbandit.record.record.container.FlacContainer
import com.llfbandit.record.record.container.IContainerWriter

class FlacFormat : Format() {
    private val sampleRates = intArrayOf(
        8000, 11025, 22050, 44100, 48000
    )

    override val mimeTypeAudio: String = MediaFormat.MIMETYPE_AUDIO_FLAC
    override val passthrough: Boolean = false

    override fun getMediaFormat(config: RecordConfig): MediaFormat {
        val format = MediaFormat().apply {
            setString(MediaFormat.KEY_MIME, mimeTypeAudio)
            setInteger(MediaFormat.KEY_SAMPLE_RATE, nearestValue(sampleRates, config.sampleRate))
            setInteger(MediaFormat.KEY_CHANNEL_COUNT, config.numChannels)

            // Specifics
            setInteger(MediaFormat.KEY_BIT_RATE, 0)
            setInteger(MediaFormat.KEY_FLAC_COMPRESSION_LEVEL, 8)
        }

        return format
    }

    override fun getContainer(path: String?): IContainerWriter {
        if (path == null) {
            throw IllegalArgumentException("Path not provided. Stream is not supported.")
        }

        return FlacContainer(path)
    }
}