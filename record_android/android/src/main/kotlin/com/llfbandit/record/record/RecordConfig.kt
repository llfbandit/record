package com.llfbandit.record.record

import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaRecorder

class RecordConfig(
    val path: String?,
    encoder: String,
    val bitRate: Int,
    val sampleRate: Int,
    numChannels: Int,
    val device: AudioDeviceInfo?,
    val autoGain: Boolean = false,
    val echoCancel: Boolean = false,
    val noiseSuppress: Boolean = false,
    val useLegacy: Boolean = false,
    val muteAudio: Boolean = false,
    val manageBluetooth: Boolean = true,
    val audioSource: Int = MediaRecorder.AudioSource.DEFAULT,
    val speakerphone: Boolean = false,
    val audioManagerMode: Int = AudioManager.MODE_NORMAL,
    audioInterruption: Int,
    val streamBufferSize: Int?
) {
    val numChannels: Int = 2.coerceAtMost(1.coerceAtLeast(numChannels))
    val audioInterruption: AudioInterruption = when (audioInterruption) {
        0 -> AudioInterruption.NONE
        1 -> AudioInterruption.PAUSE
        2 -> AudioInterruption.PAUSE_RESUME
        else -> AudioInterruption.PAUSE
    }

    val encoder: AudioEncoder = when (encoder) {
        "aacLc" -> AudioEncoder.AacLc
        "aacEld" -> AudioEncoder.AacEld
        "aacHe" -> AudioEncoder.AacHe
        "amrNb" -> AudioEncoder.AmrNb
        "amrWb" -> AudioEncoder.AmrWb
        "flac" -> AudioEncoder.Flac
        "pcm16bits" -> AudioEncoder.Pcm16bits
        "opus" -> AudioEncoder.Opus
        "wav" -> AudioEncoder.Wav
        else -> AudioEncoder.AacLc
    }
}

enum class AudioEncoder(val value: String) {
    AacLc("aacLc"),
    AacEld("aacEld"),
    AacHe("aacHe"),
    AmrNb("amrNb"),
    AmrWb("amrWb"),
    Flac("flac"),
    Pcm16bits("pcm16bits"),
    Opus("opus"),
    Wav("wav")
}

enum class AudioInterruption {
    NONE,
    PAUSE,
    PAUSE_RESUME
}