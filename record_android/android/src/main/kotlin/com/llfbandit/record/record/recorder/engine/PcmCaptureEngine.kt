package com.llfbandit.record.record.recorder.engine

import android.media.AudioDeviceInfo
import android.os.Handler
import com.llfbandit.record.record.encoder.IEncoder
import com.llfbandit.record.record.format.Format
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.recorder.AudioDeadObjectException
import com.llfbandit.record.record.recorder.PCMReader
import com.llfbandit.record.record.recorder.PcmSource
import com.llfbandit.record.record.recorder.PcmSourceFactory
import com.llfbandit.record.record.util.Utils

/** [CaptureEngine] that records with AudioRecord + an [IEncoder]; everything runs on the caller's thread. */
class PcmCaptureEngine(
  private val config: RecordConfig,
  private val onEvent: (source: CaptureEngine, event: CaptureEvent) -> Unit,
  private val removals: DeviceRemovals,
  // The control thread: reads are scheduled on it, and routing callbacks land on it.
  private val handler: Handler,
  private val hasInputDevices: () -> Boolean,
  private val createSource: PcmSourceFactory = ::PCMReader,
) : CaptureEngine {
  companion object {
    // Well under the source's buffer, so a busy control thread loses no audio.
    internal const val READ_PERIOD_MS = 20L
  }

  // Null before start, after stop and after a failure.
  private var reader: PcmSource? = null
  private var encoder: IEncoder? = null
  private var unwatchRemovals: AutoCloseable? = null
  private val route = RouteTracker()
  private val readTick = Runnable { readAvailable() }
  private var paused = false
  // The reader can't read again until it is rebuilt.
  private var needsRebuild = false
  private val capturing get() = !paused && !needsRebuild

  override val amplitude: Double
    get() = reader?.takeIf { capturing }?.getAmplitude() ?: DEFAULT_AMPLITUDE_DB

  override fun start(): RecordConfig {
    val negotiated: RecordConfig
    try {
      Format.checkStreamSupport(config)
      val (enc, mediaFormat, settled) = Format.createEncoder(config) { onEvent(this, CaptureEvent.Chunk(it)) }
      negotiated = settled
      // Assigned first so a reader failure still stops the encoder.
      encoder = enc
      val r = createSource(negotiated, mediaFormat)
      reader = r
      // A slow codec start would overrun AudioRecord's buffer.
      enc.startEncoding()
      if (!startCapture(r)) throw Exception("PCM reader failed to start.")
      // Track moves, so an unplug of the device capture just left still counts as a loss.
      r.watchRoute(handler) { reader?.let { route.moved(it.routedDevice) } }
      // Only an unplug is a loss: a route change alone may be a newly plugged device.
      unwatchRemovals = removals.watch { if (route.lost(it)) reportRouteLost() }
    } catch (e: Exception) {
      // The throw already carries the cause.
      release()
      throw e
    }

    scheduleRead()
    return negotiated
  }

  override fun pause(): Boolean {
    val r = reader ?: return false
    handler.removeCallbacks(readTick)
    // Audio captured since the last tick would be lost once AudioRecord stops.
    when (val e = readRemaining(flush = false)) {
      null -> {}
      // Resume rebuilds it.
      is AudioDeadObjectException -> needsRebuild = true
      else -> throw fail(e)
    }
    paused = true
    // A running AudioRecord keeps recording, which resume would encode as if nothing happened.
    if (!needsRebuild) r.stop()
    return true
  }

  override fun resume(device: AudioDeviceInfo?): Bound {
    val r = reader ?: throw IllegalStateException("Capture cannot resume.")
    if (!route.isLost && !needsRebuild) {
      if (startCapture(r)) {
        paused = false
        scheduleRead()
        return Bound.Resumed
      }
      // The device can vanish while stopped, and no routing callback fires when it does.
      needsRebuild = true
    }
    return captureOn(device)
  }

  override fun captureOn(device: AudioDeviceInfo?): Bound.Move {
    val r = reader ?: return Bound.NoInput
    return try {
      moveCapture(r, device)
    } catch (e: Exception) {
      Bound.Failed(fail(e))
    }
  }

  override fun stop(delete: Boolean): Throwable? {
    handler.removeCallbacks(readTick)
    // The end of the take: what AudioRecord still holds and the unfinished chunk.
    val readError = readRemaining(flush = true)
    // A device gone at the very end is no failure.
    val error = release() ?: readError?.takeUnless { it is AudioDeadObjectException }
    if (delete) Utils.deleteFile(config.path)
    return error
  }

  private fun moveCapture(r: PcmSource, device: AudioDeviceInfo?): Bound.Move {
    // A stopped reader may be dead yet claim to start, and paused, rebuilding costs no audio.
    if (needsRebuild || paused) {
      try {
        r.recreate(device)
      } catch (e: Exception) {
        // Anything else (a revoked permission, a broken config) won't fix itself on a retry.
        if (!hasInputDevices()) return Bound.NoInput
        throw e
      }
    } else {
      // A live AudioRecord can switch device without a rebuild.
      r.preferDevice(device)
    }

    if (!startCapture(r)) {
      // A reader that failed to start can't be read: wait for a rebuild instead.
      needsRebuild = true
      return Bound.NoInput
    }

    needsRebuild = false
    paused = false
    scheduleRead()
    return Bound.On(boundTo(device, r.routedDevice?.id))
  }

  // The device is unknown until Android has picked one, so read it again here.
  private fun startCapture(r: PcmSource): Boolean {
    val started = try {
      r.start()
    } catch (_: Exception) {
      false
    }
    if (started) route.reset(r.routedDevice)
    return started
  }

  private fun scheduleRead() {
    handler.removeCallbacks(readTick)
    handler.postDelayed(readTick, READ_PERIOD_MS)
  }

  private fun readAvailable() {
    // A read scheduled before capture halted must not touch a stopped or dead reader.
    if (!capturing) return
    val r = reader ?: return
    val enc = encoder ?: return
    try {
      encodeAvailable(r, enc)
    } catch (_: AudioDeadObjectException) {
      // The device went away without the framework re-routing us anywhere.
      needsRebuild = true
      reportRouteLost()
      return
    } catch (e: Exception) {
      onEvent(this, CaptureEvent.Failed(fail(e)))
      return
    }
    scheduleRead()
  }

  private fun encodeAvailable(r: PcmSource, enc: IEncoder) {
    while (true) {
      val chunk = r.read()
      if (chunk.isEmpty()) break
      enc.encode(chunk)
    }
    enc.pump()
  }

  /** Encodes what capture holds but has not handed over yet; returns a failure instead of reporting it. */
  private fun readRemaining(flush: Boolean): Throwable? {
    val r = reader ?: return null
    val enc = encoder ?: return null
    return try {
      // A stopped or dead reader has nothing new.
      if (capturing) encodeAvailable(r, enc)
      if (flush) r.flush().takeIf { it.isNotEmpty() }?.let(enc::encode)
      null
    } catch (e: Exception) {
      e
    }
  }

  private fun reportRouteLost() {
    if (route.report()) onEvent(this, CaptureEvent.RouteLost)
  }

  private fun fail(cause: Throwable): Throwable {
    handler.removeCallbacks(readTick)
    release()
    return cause
  }

  private fun release(): Throwable? {
    val r = reader
    val enc = encoder
    reader = null
    encoder = null
    unwatchRemovals?.close()
    unwatchRemovals = null

    var error: Throwable? = null
    try {
      r?.release()
    } catch (e: Exception) {
      error = e
    }

    // Stopped even after a reader failure, so the file still gets its trailer.
    val encoderError = enc?.stopEncoding()
    return error ?: encoderError
  }
}
