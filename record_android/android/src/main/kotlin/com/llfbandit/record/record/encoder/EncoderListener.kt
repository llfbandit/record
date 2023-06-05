package com.llfbandit.record.record.encoder

import java.nio.ByteBuffer

interface EncoderListener {
    /**
     * Callback when encoder need to size its own buffer
     *
     * @return The number of bytes to allocate.
     */
    fun onEncoderDataSize(): Int

    /**
     * Callback when encoder need more data to encode
     * @param byteBuffer The data buffer to fill.
     *
     * @return The number of bytes read.
     */
    fun onEncoderDataNeeded(byteBuffer: ByteBuffer): Int

    /**
     * Called when an error occured during the encoding process
     */
    fun onEncoderFailure(ex: Exception)

    /**
     * Provides encoded data available for streaming
     */
    fun onEncoderStream(bytes: ByteArray)

    /**
     * Called when the encoder has stopped
     */
    fun onEncoderStop()
}