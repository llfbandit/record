package com.llfbandit.record.record.recorder

import com.llfbandit.record.record.RecordConfig

interface IRecorder {
    @Throws(Exception::class)
    fun start(config: RecordConfig)

    /**
     * Stops the recording.
     */
    fun stop(stopCb: ((path: String?) -> Unit)?)

    /**
     * Stops the recording and delete file.
     */
    fun cancel()

    /**
     * Pauses the recording if currently running.
     */
    fun pause()

    /**
     * Resumes the recording if currently paused.
     */
    fun resume()

    /**
     * Gets the state the of recording
     *
     * @return True if recording. False otherwise.
     */
    val isRecording: Boolean

    /**
     * Gets the state the of recording
     *
     * @return True if paused. False otherwise.
     */
    val isPaused: Boolean

    /**
     * Gets the amplitude
     *
     * @return List with current and max amplitude values
     */
    fun getAmplitude(): List<Double>

    fun dispose()
}