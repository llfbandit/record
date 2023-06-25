package com.llfbandit.record.record.encoder

interface IEncoder {
    /**
     * Start the encoder process.
     *
     * Can only be called if the encoder process is not already started.
     */
    fun start()

    /**
     * Stop the encoder process.
     *
     * Can only be called if the encoder process is started.
     */
    fun stop()

    /**
     * Release resources used by the encoder process.
     *
     * If the encoder process is not already stopped, then it will be stopped.
     */
    fun release()
}