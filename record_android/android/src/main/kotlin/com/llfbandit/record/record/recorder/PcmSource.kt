package com.llfbandit.record.record.recorder

import android.media.AudioDeviceInfo
import android.media.MediaFormat
import com.llfbandit.record.record.model.RecordConfig

/** Creates the source a capture engine reads from. [PCMReader] is the real one, backed by AudioRecord. */
typealias PcmSourceFactory = (RecordConfig, MediaFormat) -> PcmSource

/** The PCM feed of one recording; only [getAmplitude] runs off the capture loop's thread. */
interface PcmSource {
  /** @return false, not a throw, when the framework refuses to start capture. */
  fun start(): Boolean

  fun stop()

  fun release()

  /** @throws AudioDeadObjectException when the device it was reading from is gone. */
  @Throws(Exception::class)
  fun read(): ByteArray

  fun getAmplitude(): Double

  /** Id of the device in use, or null while stopped or before Android picks one. */
  val routedDeviceId: Int?

  /** Calls [onChanged] whenever the framework moves capture to another device. */
  fun watchRoute(onChanged: () -> Unit)

  /** Pins capture to [device]; null lets the framework pick. */
  fun preferDevice(device: AudioDeviceInfo?)

  /** Rebuilds capture pinned to [device], or unpinned when null; the caller starts it. */
  @Throws(Exception::class)
  fun recreate(device: AudioDeviceInfo?)
}
