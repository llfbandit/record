package com.llfbandit.record.record.recorder.engine

import android.media.AudioDeviceInfo
import com.llfbandit.record.record.encoder.EncoderListener
import com.llfbandit.record.record.encoder.IEncoder
import com.llfbandit.record.record.format.Format
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.recorder.AudioDeadObjectException
import com.llfbandit.record.record.recorder.PCMReader
import com.llfbandit.record.record.recorder.PcmSource
import com.llfbandit.record.record.recorder.PcmSourceFactory
import com.llfbandit.record.record.util.Utils
import java.util.concurrent.LinkedBlockingQueue

/** [CaptureEngine] that records with AudioRecord + an [IEncoder] on a background loop. */
class PcmCaptureEngine(
  config: RecordConfig,
  private val onEvent: (source: CaptureEngine, event: CaptureEvent) -> Unit,
  private val removals: DeviceRemovals,
  private val createSource: PcmSourceFactory = ::PCMReader,
) : CaptureEngine, EncoderListener {
  companion object {
    // The hardware needs a moment to switch to the device that replaces the lost one.
    private const val MAX_REROUTE_ATTEMPTS = 3
    private const val REROUTE_RETRY_DELAY_MS = 150L
  }

  // Every thread posts here, because only the loop may touch the reader.
  private sealed interface Msg {
    data object Pause : Msg
    data object Resume : Msg
    data object RouteChanged : Msg
    class DevicesRemoved(val deviceIds: List<Int>) : Msg
    class Reroute(val device: AudioDeviceInfo?, val done: (Boolean) -> Unit) : Msg
    class Stop(val delete: Boolean, val done: (Throwable?) -> Unit) : Msg
    class EncoderFailed(val cause: Throwable) : Msg
  }

  // Keep a private copy: renegotiating the codec must not change the caller's config.
  private val config: RecordConfig = config.copy()
  private val inbox = LinkedBlockingQueue<Msg>()

  // The loop sets it to null; the control thread reads it for the amplitude.
  @Volatile private var reader: PcmSource? = null
  private var encoder: IEncoder? = null
  private var thread: Thread? = null
  // The loop sets it on a failure; the control thread reads it to refuse requests.
  @Volatile private var failed = false
  private var unwatchRemovals: AutoCloseable? = null

  override val amplitude: Double get() = reader?.getAmplitude() ?: DEFAULT_AMPLITUDE_DB

  override fun reroute(device: AudioDeviceInfo?, done: (ok: Boolean) -> Unit) {
    // Only the loop touches the reader, so the answer comes from there.
    if (!post(Msg.Reroute(device, done))) done(false)
  }

  override fun start(): RecordConfig {
    try {
      Format.checkStreamSupport(config)
      val (enc, mediaFormat) = Format.createEncoder(config, this)
      // Assigned first so a reader failure still releases the container it opened.
      encoder = enc
      val r = createSource(config, mediaFormat)
      reader = r
      if (!r.start()) throw Exception("PCM reader failed to start.")
      // Track moves, so an unplug of the device capture just left still counts as a loss.
      r.watchRoute { inbox.put(Msg.RouteChanged) }
      // Only an unplug is a loss: a route change alone may be a newly plugged device.
      unwatchRemovals = removals.watch { inbox.put(Msg.DevicesRemoved(it)) }
      enc.startEncoding()
    } catch (e: Exception) {
      // The throw already carries the cause.
      release {}
      throw e
    }

    thread = Thread(::pump, "record-capture-${config.path ?: "stream"}").apply {
      isDaemon = true
      start()
    }
    return config
  }

  override fun pause(): Boolean = post(Msg.Pause)

  override fun resume(): Boolean = post(Msg.Resume)

  override fun stop(delete: Boolean, done: (Throwable?) -> Unit) {
    val t = thread
    thread = null

    // Never started: only the encoder's container is left.
    if (t == null) {
      release { error -> answer(delete, error, done) }
      return
    }
    // The loop owns the teardown, so it answers.
    inbox.put(Msg.Stop(delete, done))
  }

  override fun onEncoderFailure(ex: Exception) {
    inbox.put(Msg.EncoderFailed(ex))
  }

  override fun onEncoderStream(bytes: ByteArray) = onEvent(this, CaptureEvent.Chunk(bytes))

  private fun post(msg: Msg): Boolean {
    val t = thread ?: return false
    // A failed or exited loop answers nothing, so pause and resume must not look like they worked.
    if (failed || !t.isAlive) return false
    inbox.put(msg)
    return true
  }

  private fun pump() {
    val reader = checkNotNull(reader)
    val encoder = checkNotNull(encoder)
    var paused = false
    // The reader can't read again until it is rebuilt, so the loop must stop calling read().
    var needsRebuild = false
    // Keeps reportRouteLost from repeating until a reroute or pause answers it.
    var routePending = false
    val route = RouteTracker().apply { reset(reader.routedDeviceId) }
    var failure: Throwable

    fun reportRouteLost() {
      if (routePending) return
      routePending = true
      onEvent(this, CaptureEvent.RouteLost)
    }

    // The device is unknown until Android has picked one, so read it again here.
    fun startCapture(): Boolean {
      val started = try {
        reader.start()
      } catch (_: Exception) {
        false
      }
      if (started) route.reset(reader.routedDeviceId)
      return started
    }

    fun reroute(device: AudioDeviceInfo?): Boolean {
      if (needsRebuild) {
        if (!recreate(reader, device)) return false
      } else {
        // A live AudioRecord can switch device without a rebuild.
        reader.preferDevice(device)
      }

      // The reader stays stopped while paused, rebuilt or not; resume() starts it.
      if (paused) {
        route.reset(null)
      } else if (!startCapture()) {
        // A reader that failed to start can't be read: wait for a rebuild instead.
        needsRebuild = true
        return false
      }

      needsRebuild = false
      return true
    }

    capture@ while (true) {
      when (val msg = if (paused || needsRebuild) inbox.take() else inbox.poll()) {
        null -> {}
        Msg.Pause -> {
          paused = true
          routePending = false
          // A running AudioRecord keeps recording, which resume would encode as if nothing happened.
          if (!needsRebuild) reader.stop()
        }

        Msg.Resume -> {
          paused = false
          // The device can vanish while stopped; no routing callback fires when it does.
          if (!startCapture()) {
            needsRebuild = true
            reportRouteLost()
          }
        }

        Msg.RouteChanged -> route.moved(reader.routedDeviceId)

        is Msg.DevicesRemoved -> if (route.lost(msg.deviceIds)) reportRouteLost()

        is Msg.Reroute -> {
          val ok = reroute(msg.device)
          routePending = false
          msg.done(ok)
        }

        is Msg.Stop -> return release { error -> answer(msg.delete, error, msg.done) }
        is Msg.EncoderFailed -> { failure = msg.cause; break@capture }
      }
      if (paused || needsRebuild) continue

      try {
        val buffer = reader.read()
        if (buffer.isNotEmpty()) encoder.encode(buffer)
      } catch (e: AudioDeadObjectException) {
        // The device went away without the framework re-routing us anywhere.
        needsRebuild = true
        reportRouteLost()
      } catch (e: Exception) {
        failure = e
        break@capture
      }
    }

    failed = true
    // Stays alive after releasing: the stop that follows must still be answered.
    release {}
    onEvent(this, CaptureEvent.Failed(failure))
    while (true) {
      when (val msg = inbox.take()) {
        is Msg.Stop -> return answer(msg.delete, failure, msg.done)
        // The reader is released, so refuse the reroute but still answer the caller.
        is Msg.Reroute -> msg.done(false)
        else -> {}
      }
    }
  }

  private fun recreate(reader: PcmSource, device: AudioDeviceInfo?): Boolean {
    repeat(MAX_REROUTE_ATTEMPTS) { attempt ->
      if (attempt > 0) {
        try {
          Thread.sleep(REROUTE_RETRY_DELAY_MS)
        } catch (_: InterruptedException) {
          return false
        }
      }

      try {
        reader.recreate(device)
        return true
      } catch (_: Exception) {
        // The replacement device may not be there yet.
      }
    }
    return false
  }

  /** Releases both halves regardless of failure; reports the first error. */
  private fun release(done: (Throwable?) -> Unit) {
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

    if (enc == null) done(error) else enc.stopEncoding { done(error ?: it) }
  }

  private fun answer(delete: Boolean, error: Throwable?, done: (Throwable?) -> Unit) {
    if (delete) Utils.deleteFile(config.path)
    done(error)
  }
}
