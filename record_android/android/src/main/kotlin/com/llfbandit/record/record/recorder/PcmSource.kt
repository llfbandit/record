package com.llfbandit.record.record.recorder

import android.media.AudioDeviceInfo
import android.media.MediaFormat
import android.os.Handler
import com.llfbandit.record.record.model.RecordConfig

/** Creates the source a capture engine reads from. [PCMReader] is the real one, backed by AudioRecord. */
typealias PcmSourceFactory = (RecordConfig, MediaFormat) -> PcmSource

/** The PCM feed of one recording; every call runs on the control thread. */
interface PcmSource {
  /** @return false, not a throw, when the framework refuses to start capture. */
  fun start(): Boolean

  fun stop()

  fun release()

  /**
   * Never blocks: returns the next full chunk, or an empty array until one is captured.
   * @throws AudioDeadObjectException when the device it was reading from is gone.
   */
  @Throws(Exception::class)
  fun read(): ByteArray

  /** Hands over the unfinished chunk read so far; empty when there is none. */
  fun flush(): ByteArray

  fun getAmplitude(): Double

  /** The device in use, or null while stopped or before Android picks one. */
  val routedDevice: AudioDeviceInfo?

  /** Calls [onChanged] on [handler] whenever the framework moves capture to another device. */
  fun watchRoute(handler: Handler, onChanged: () -> Unit)

  /** Pins capture to [device]; null lets the framework pick. */
  fun preferDevice(device: AudioDeviceInfo?)

  /** Rebuilds capture pinned to [device], or unpinned when null, retrying briefly; the caller starts it. */
  @Throws(Exception::class)
  fun recreate(device: AudioDeviceInfo?)
}
