package com.llfbandit.record.record.recorder.engine

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioRouting
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.util.Log
import com.llfbandit.record.record.format.Format
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.util.Utils

/** [CaptureEngine] backed by the framework [MediaRecorder]; everything runs on the caller's thread. */
class MediaCaptureEngine(
  private val context: Context,
  private val config: RecordConfig,
  private val onEvent: (source: CaptureEngine, event: CaptureEvent) -> Unit,
  private val removals: DeviceRemovals,
  // The control thread, so every routing callback lands where the engine runs.
  private val handler: Handler,
  private val hasInputDevices: () -> Boolean,
) : CaptureEngine {
  companion object {
    private val TAG = MediaCaptureEngine::class.java.simpleName
  }

  private var recorder: MediaRecorder? = null
  private var routingListener: AudioRouting.OnRoutingChangedListener? = null
  private var unwatchRemovals: AutoCloseable? = null
  private val route = RouteTracker()
  private var paused = false

  override val amplitude: Double
    get() {
      val r = recorder ?: return DEFAULT_AMPLITUDE_DB
      val peak = try {
        r.maxAmplitude
      } catch (_: RuntimeException) {
        0
      }
      return peakToDb(peak)
    }

  // MediaRecorder re-routes itself; it only needs the pin moved and to run.
  override fun captureOn(device: AudioDeviceInfo?): Bound.Move {
    val r = recorder ?: return Bound.NoInput
    if (!hasInputDevices()) return Bound.NoInput
    preferDevice(r, device)
    if (paused) {
      try {
        resumeRecorder(r)
      } catch (e: IllegalStateException) {
        return Bound.Failed(e)
      }
    }
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return Bound.On(null)

    val routed = r.routedDevice
    route.reset(routed)
    return Bound.On(boundTo(device, routed?.id))
  }

  // MediaRecorder only takes a preferred device from API 28; below that, Android picks.
  private fun preferDevice(r: MediaRecorder, device: AudioDeviceInfo?) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && !r.setPreferredDevice(device)) {
      Log.w(TAG, "Unable to set device: ${device?.productName}")
    }
  }

  override fun start(): RecordConfig {
    val legacy = Format.selectFormat(config.encoder).legacyRecorder(config)
      ?: throw IllegalArgumentException("The legacy recorder cannot record '${config.encoder.value}'.")

    val r = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
      @Suppress("DEPRECATION")
      MediaRecorder()
    } else {
      MediaRecorder(context)
    }

    // The setters throw too (unsupported source, rejected format): never leak the native recorder.
    try {
      r.setAudioSource(config.audioSource)
      r.setAudioEncodingBitRate(config.bitRate)
      r.setAudioSamplingRate(config.sampleRate)
      r.setAudioChannels(2.coerceAtMost(1.coerceAtLeast(config.numChannels)))
      r.setOutputFormat(legacy.outputFormat)
      // must be set after output format
      r.setAudioEncoder(legacy.audioEncoder)
      r.setOutputFile(config.path)
      preferDevice(r, config.device)
      r.prepare()
      r.start()
    } catch (e: Exception) {
      r.release()
      throw e
    }

    recorder = r
    watchRoute(r)
    return config
  }

  // MediaRecorder only reports its route from API 28, so below that no route change is handled.
  private fun watchRoute(r: MediaRecorder) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return

    route.reset(r.routedDevice)
    val listener = AudioRouting.OnRoutingChangedListener {
      // Ignore callbacks that arrive after stop() released the recorder.
      recorder?.let { route.moved(it.routedDevice) }
    }
    routingListener = listener
    r.addOnRoutingChangedListener(listener, handler)

    // Only an unplug is a loss: a route change alone may be a newly plugged device.
    unwatchRemovals = removals.watch { deviceIds ->
      if (recorder != null && route.lost(deviceIds) && route.report()) onEvent(this, CaptureEvent.RouteLost)
    }
  }

  override fun pause(): Boolean {
    val r = recorder ?: return false
    return try {
      r.pause()
      paused = true
      true
    } catch (ex: IllegalStateException) {
      Log.d(TAG, "pause() called before start() or after stop(): ${ex.message}")
      false
    }
  }

  override fun resume(device: AudioDeviceInfo?): Bound {
    if (route.isLost) return captureOn(device)
    val r = recorder ?: throw IllegalStateException("Capture cannot resume.")
    try {
      resumeRecorder(r)
    } catch (e: IllegalStateException) {
      throw IllegalStateException("Capture cannot resume.", e)
    }
    return Bound.Resumed
  }

  @Throws(IllegalStateException::class)
  private fun resumeRecorder(r: MediaRecorder) {
    r.resume()
    paused = false
  }

  override fun stop(delete: Boolean): Throwable? {
    val r = recorder
    recorder = null
    var error: Throwable? = null

    if (r != null) {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        routingListener?.let { r.removeOnRoutingChangedListener(it) }
      }
      routingListener = null
      unwatchRemovals?.close()
      unwatchRemovals = null
      try {
        r.stop()
      } catch (_: RuntimeException) {
        // stop() throws when nothing was captured, which is fine here.
      } finally {
        // Reported, never thrown: the caller still has a session to finish.
        try {
          r.reset()
          r.release()
        } catch (e: Exception) {
          error = e
        }
      }
    }

    if (delete) Utils.deleteFile(config.path)

    return error
  }
}
