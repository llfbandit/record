package com.llfbandit.record.record.encoder

interface EncoderListener {
    /**
     * Called when an error occured during the encoding process
     */
    fun onEncoderFailure(ex: Exception)

    /**
     * Provides encoded data available for streaming
     */
    fun onEncoderStream(bytes: ByteArray)
}