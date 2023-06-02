package com.llfbandit.record.record

/**
 * @param path         The output path to write the file.
 * @param encoder      The encoder enum index from dart side.
 * @param bitRate      The bit rate of encoded file.
 * @param sampleRate The sampling rate of encoded file.
 * @param numChannels  The number of channels (1 or 2).
 * //@param device       The input device to acquire audio data.
 * @param autoGain     Enables automatic gain control if available.
 * @param echoCancel   Enables echo cancellation if available.
 * @param noiseCancel  Enables noise cancellation if available.
 */
class RecordConfig(
    val path: String?,
    val encoder: String,
    val bitRate: Int,
    val sampleRate: Int,
    numChannels: Int,
    //val device: Map<String, Any>?,
    val autoGain: Boolean = false,
    val echoCancel: Boolean = false,
    val noiseCancel: Boolean = false
) {
    val numChannels: Int

    init {
        this.numChannels = 2.coerceAtMost(1.coerceAtLeast(numChannels))
    }
}