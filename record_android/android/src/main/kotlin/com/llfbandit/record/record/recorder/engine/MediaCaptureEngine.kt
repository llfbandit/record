package com.llfbandit.record.record.recorder.engine

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import android.util.Log
import com.llfbandit.record.record.model.AudioEncoder
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.util.Utils
import kotlin.math.log10

/** [CaptureEngine] backed by the framework [MediaRecorder]; everything runs on the caller's thread. */
class MediaCaptureEngine(
  private val context: Context,
  config: RecordConfig,
) : CaptureEngine {
  companion object {
    private val TAG = MediaCaptureEngine::class.java.simpleName
  }

  private val config: RecordConfig = config.copy()
  private var recorder: MediaRecorder? = null

  override val amplitude: Double
    get() {
      val r = recorder ?: return DEFAULT_AMPLITUDE_DB
      val peak = try {
        r.maxAmplitude
      } catch (_: RuntimeException) {
        0
      }
      return if (peak == 0) DEFAULT_AMPLITUDE_DB else 20 * log10(peak / 32768.0)
    }

  override fun start(): RecordConfig {
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
      r.setOutputFormat(getOutputFormat(config.encoder))
      // must be set after output format
      r.setAudioEncoder(getEncoder(config.encoder))
      r.setOutputFile(config.path)
      r.prepare()
      r.start()
    } catch (e: Exception) {
      r.release()
      throw e
    }

    recorder = r
    return config
  }

  override fun pause(): Boolean {
    val r = recorder ?: return false
    return try {
      r.pause()
      true
    } catch (ex: IllegalStateException) {
      Log.d(TAG, "pause() called before start() or after stop(): ${ex.message}")
      false
    }
  }

  override fun resume(): Boolean {
    val r = recorder ?: return false
    return try {
      r.resume()
      true
    } catch (ex: IllegalStateException) {
      Log.d(TAG, "resume() called before start() or after stop(): ${ex.message}")
      false
    }
  }

  override fun stop(delete: Boolean, done: (Throwable?) -> Unit) {
    val r = recorder
    recorder = null
    var error: Throwable? = null

    if (r != null) {
      try {
        r.stop()
      } catch (_: RuntimeException) {
        // Muted: stop() throws if no valid data was captured.
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

    done(error)
  }

  private fun getOutputFormat(encoder: AudioEncoder): Int = when (encoder) {
    AudioEncoder.AacLc, AudioEncoder.AacEld, AudioEncoder.AacHe -> MediaRecorder.OutputFormat.MPEG_4
    AudioEncoder.AmrNb, AudioEncoder.AmrWb -> MediaRecorder.OutputFormat.THREE_GPP
    AudioEncoder.Opus ->
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) MediaRecorder.OutputFormat.OGG
      else MediaRecorder.OutputFormat.MPEG_4
    else -> MediaRecorder.OutputFormat.DEFAULT
  }

  // https://developer.android.com/reference/android/media/MediaRecorder.AudioEncoder
  private fun getEncoder(encoder: AudioEncoder): Int = when (encoder) {
    AudioEncoder.AacLc -> MediaRecorder.AudioEncoder.AAC
    AudioEncoder.AacEld -> MediaRecorder.AudioEncoder.AAC_ELD
    AudioEncoder.AacHe -> MediaRecorder.AudioEncoder.HE_AAC
    AudioEncoder.AmrNb -> MediaRecorder.AudioEncoder.AMR_NB
    AudioEncoder.AmrWb -> MediaRecorder.AudioEncoder.AMR_WB
    AudioEncoder.Opus ->
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        MediaRecorder.AudioEncoder.OPUS
      } else {
        Log.d(TAG, "Falling back to AAC LC")
        MediaRecorder.AudioEncoder.AAC
      }
    else -> {
      Log.d(TAG, "Falling back to AAC LC")
      MediaRecorder.AudioEncoder.AAC
    }
  }
}
