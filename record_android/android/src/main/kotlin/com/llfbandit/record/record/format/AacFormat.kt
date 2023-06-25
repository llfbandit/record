package com.llfbandit.record.record.format

import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import com.llfbandit.record.record.AudioEncoder
import com.llfbandit.record.record.RecordConfig
import com.llfbandit.record.record.container.AdtsContainer
import com.llfbandit.record.record.container.IContainerWriter
import com.llfbandit.record.record.container.MuxerContainer

class AacFormat : Format() {
    private val sampleRates = intArrayOf(
        96000,
        88200,
        64000,
        48000,
        44100,
        32000,
        24000,
        22050,
        16000,
        12000,
        11025,
        8000
    )

    override val mimeTypeAudio: String = MediaFormat.MIMETYPE_AUDIO_AAC
    override val passthrough: Boolean = false

    private var sampleRate: Int = 44100
    private var numChannels: Int = 2
    private var aacProfile: Int = MediaCodecInfo.CodecProfileLevel.AACObjectLC

    override fun getMediaFormat(config: RecordConfig): MediaFormat {
        val format = MediaFormat().apply {
            setString(MediaFormat.KEY_MIME, mimeTypeAudio)
            setInteger(MediaFormat.KEY_SAMPLE_RATE, nearestValue(sampleRates, sampleRate))
            setInteger(MediaFormat.KEY_CHANNEL_COUNT, numChannels)
            setInteger(MediaFormat.KEY_BIT_RATE, config.bitRate)

            // Specifics
            when (config.encoder) {
                AudioEncoder.aacLc -> setInteger(
                    MediaFormat.KEY_AAC_PROFILE,
                    MediaCodecInfo.CodecProfileLevel.AACObjectLC
                )

                AudioEncoder.aacEld -> setInteger(
                    MediaFormat.KEY_AAC_PROFILE,
                    MediaCodecInfo.CodecProfileLevel.AACObjectELD
                )

                AudioEncoder.aacHe -> setInteger(
                    MediaFormat.KEY_AAC_PROFILE,
                    MediaCodecInfo.CodecProfileLevel.AACObjectHE
                )
            }
        }

        sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        numChannels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        aacProfile = format.getInteger(MediaFormat.KEY_AAC_PROFILE)

        return format
    }

    override fun getContainer(path: String?): IContainerWriter {
        if (path == null) {
            return AdtsContainer(sampleRate, numChannels, aacProfile)
        }

        return MuxerContainer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    }
}