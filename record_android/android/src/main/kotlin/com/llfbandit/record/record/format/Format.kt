package com.llfbandit.record.record.format

import android.media.MediaFormat
import com.llfbandit.record.record.RecordConfig
import com.llfbandit.record.record.container.IContainerWriter
import com.llfbandit.record.record.encoder.EncoderListener
import com.llfbandit.record.record.encoder.IEncoder
import com.llfbandit.record.record.encoder.MediaCodecEncoder
import com.llfbandit.record.record.encoder.PassthroughEncoder
import kotlin.math.abs

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

    /**
     * Create an encoder that produces [MediaFormat] output.
     *
     * @throws Exception if the device does not support encoding with the parameters set in
     * [mediaFormat] or if configuring the encoder fails.
     */
    fun getEncoder(
        config: RecordConfig,
        listener: EncoderListener
    ): IEncoder {

        val mediaFormat = getMediaFormat(config)
        val container = getContainer(config.path)

        return if (passthrough) {
            PassthroughEncoder(mediaFormat, listener, container)
        } else {
            MediaCodecEncoder(mediaFormat, listener, container)
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
            val cdistance = abs(values[c] - value)
            if (cdistance < distance) {
                idx = c
                distance = cdistance
            }
        }
        return values[idx]
    }

    companion object {
        const val KEY_X_FRAME_SIZE_IN_BYTES = "x-frame-size-in-bytes"
    }
}