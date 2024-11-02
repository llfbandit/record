package com.llfbandit.record.record.encoder

interface IEncoder {
    /**
     * Start the encoder process.
     *
     * Can only be called if the encoder process is not already started.
     */
    fun startEncoding()

    /**
     * Stop the encoder process.
     * Release resources used by the encoder process.
     *
     * Can only be called if the encoder process is started.
     */
    fun stopEncoding()

    /**
     * Encode bytes of audio to file
     *
     * @param bytes - PCM input buffer
     */
    fun encode(bytes: ByteArray)
}