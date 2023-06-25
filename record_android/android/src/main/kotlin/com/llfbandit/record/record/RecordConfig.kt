package com.llfbandit.record.record

class RecordConfig(
    val path: String?,
    val encoder: String,
    val bitRate: Int,
    val sampleRate: Int,
    numChannels: Int,
    //val device: Map<String, Any>?,
    val autoGain: Boolean = false,
    val echoCancel: Boolean = false,
    val noiseSuppress: Boolean = false
) {
    val numChannels: Int

    init {
        this.numChannels = 2.coerceAtMost(1.coerceAtLeast(numChannels))
    }
}

class AudioEncoder {
    companion object {
        const val aacLc = "aacLc"
        const val aacEld = "aacEld"
        const val aacHe = "aacHe"
        const val amrNb = "amrNb"
        const val amrWb = "amrWb"
        const val flac = "flac"
        const val pcm16bits = "pcm16bits"
        const val opus = "opus"
        const val wav = "wav"
    }
}
