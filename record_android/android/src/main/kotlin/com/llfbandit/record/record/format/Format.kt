package com.llfbandit.record.record.format

import android.media.MediaFormat
import android.util.Log
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
            val cDistance = abs(values[c] - value)
            if (cDistance < distance) {
                idx = c
                distance = cDistance
            }
        }

        if (value != values[idx]) {
            Log.d(TAG, "Available values: $values")
            Log.d(TAG, "Adjusted to: $value")
        }

        return values[idx]
    }

    companion object {
        const val KEY_X_FRAME_SIZE_IN_BYTES = "x-frame-size-in-bytes"
        private val TAG = Format::class.java.simpleName
    }
}