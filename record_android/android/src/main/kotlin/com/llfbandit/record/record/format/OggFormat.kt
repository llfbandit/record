package com.llfbandit.record.record.format

import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import com.llfbandit.record.record.RecordConfig
import com.llfbandit.record.record.container.IContainerWriter
import com.llfbandit.record.record.container.MuxerContainer

class OggFormat : Format() {
    private val sampleRates = intArrayOf(
        8000, 11025, 22050, 44100, 48000
    )

    override val mimeTypeAudio: String = MediaFormat.MIMETYPE_AUDIO_VORBIS
    override val passthrough: Boolean = false

    override fun getMediaFormat(config: RecordConfig): MediaFormat {
        val format = MediaFormat().apply {
            setString(MediaFormat.KEY_MIME, mimeTypeAudio)
            setInteger(MediaFormat.KEY_SAMPLE_RATE, nearestValue(sampleRates, config.samplingRate))
            setInteger(MediaFormat.KEY_CHANNEL_COUNT, config.numChannels)
            setInteger(MediaFormat.KEY_BIT_RATE, config.bitRate)
        }

        return format
    }

    override fun getContainer(path: String?): IContainerWriter {
        if (path == null) {
            throw IllegalArgumentException("Path not provided")
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            throw IllegalAccessException("Vorbis OGG requires min API version: " + Build.VERSION_CODES.Q)
        }

        return MuxerContainer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_OGG)
    }
}