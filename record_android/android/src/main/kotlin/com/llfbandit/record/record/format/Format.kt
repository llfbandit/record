package com.llfbandit.record.record.format

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.util.Log
import android.util.Range
import com.llfbandit.record.record.RecordConfig
import com.llfbandit.record.record.container.IContainerWriter
import com.llfbandit.record.record.encoder.EncoderListener
import com.llfbandit.record.record.encoder.IEncoder
import com.llfbandit.record.record.encoder.MediaCodecEncoder
import com.llfbandit.record.record.encoder.PassthroughEncoder
import kotlin.math.abs


/**
 * Represents an audio format.
 * This class is responsible for creating the encoder and container for the specified format.
 * It also provides the [MediaFormat] for the encoded audio stream.
 */
sealed class Format {
    /**
     * The MIME type of the encoded audio stream inside the container.
     */
    abstract val mimeTypeAudio: String

    /** 'true' if the format takes PCM samples without encoding. */
    abstract val passthrough: Boolean

    /**
     * Create a [MediaFormat] representing the encoded audio with parameters matching the specified
     * input PCM audio format.
     */
    abstract fun getMediaFormat(config: RecordConfig): MediaFormat

    protected open fun adjustSampleRate(format: MediaFormat, sampleRate: Int) {
        format.setInteger(MediaFormat.KEY_SAMPLE_RATE, sampleRate)
    }

    private fun adjustBitRate(format: MediaFormat, bitRate: Int) {
        format.setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
    }

    protected open fun adjustNumChannels(format: MediaFormat, numChannels: Int) {
        format.setInteger(MediaFormat.KEY_CHANNEL_MASK, numChannels)
    }

    /**
     * Create an encoder that produces [MediaFormat] output.
     */
    fun getEncoder(
        config: RecordConfig,
        listener: EncoderListener
    ): Pair<IEncoder, MediaFormat> {

        val mediaFormat = getMediaFormat(config)

        return if (passthrough) {
            Pair(
                PassthroughEncoder(config, this, mediaFormat, listener),
                mediaFormat
            )
        } else {
            val codec = findCodecForAdjustedFormat(config, mediaFormat)
            codec ?: throw Exception(
                "No codec found for given config $mediaFormat. You should try with other values."
            )

            Pair(
                MediaCodecEncoder(config, this, mediaFormat, listener, codec),
                mediaFormat
            )
        }
    }

    /**
     * Create a container to write the encoded data.
     *
     * @param path The output path if the container writes to file.
     */
    abstract fun getContainer(path: String?): IContainerWriter

    protected fun nearestValue(values: IntArray, value: Int): Int {
        var distance: Int = abs(values[0] - value)
        var idx = 0

        for (c in 1 until values.size) {
            val cDistance = abs(values[c] - value)
            if (cDistance < distance) {
                idx = c
                distance = cDistance
            }
        }

        if (value != values[idx]) {
            Log.d(TAG, "Available values: ${values.indices.map { values[it] }}")
            Log.d(TAG, "Adjusted to: ${values[idx]}")
        }

        return values[idx]
    }

    private fun checkBounds(range: Range<Int>, value: Int): Int {
        if (range.lower > value) {
            return range.lower
        } else if (range.upper < value) {
            return range.upper
        }
        return value
    }

    private fun adjustFormat(
        caps: MediaCodecInfo.CodecCapabilities,
        config: RecordConfig,
        mediaFormat: MediaFormat
    ): Boolean {
        if (!caps.isFormatSupported(mediaFormat)) {
            adjustBitRate(
                mediaFormat,
                checkBounds(caps.audioCapabilities.bitrateRange, config.bitRate)
            )
            if (caps.audioCapabilities.supportedSampleRates != null) {
                adjustSampleRate(
                    mediaFormat,
                    nearestValue(
                        caps.audioCapabilities.supportedSampleRates,
                        config.sampleRate
                    )
                )
            }
            adjustNumChannels(
                mediaFormat,
                nearestValue(
                    intArrayOf(1, caps.audioCapabilities.maxInputChannelCount),
                    config.numChannels
                )
            )

            return caps.isFormatSupported(mediaFormat)
        }

        return true
    }

    private fun findCodecForAdjustedFormat(
        config: RecordConfig,
        mediaFormat: MediaFormat
    ): String? {
        val codecs = MediaCodecList(MediaCodecList.REGULAR_CODECS)

        for (info in codecs.codecInfos) {
            if (!info.isEncoder) {
                continue
            }

            try {
                val caps = info.getCapabilitiesForType(mimeTypeAudio)
                if (caps != null && adjustFormat(caps, config, mediaFormat)) {
                    return info.name
                }
            } catch (e: IllegalArgumentException) {
                // type is not supported
            }
        }

        return null
    }

    companion object {
        const val KEY_X_FRAME_SIZE_IN_BYTES = "x-frame-size-in-bytes"
        private val TAG = Format::class.java.simpleName
    }
}