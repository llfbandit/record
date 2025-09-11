package com.llfbandit.record.record.recorder

import com.llfbandit.record.Utils
import com.llfbandit.record.record.AudioEncoder
import com.llfbandit.record.record.PCMReader
import com.llfbandit.record.record.RecordConfig
import com.llfbandit.record.record.encoder.EncoderListener
import com.llfbandit.record.record.encoder.IEncoder
import com.llfbandit.record.record.format.AacFormat
import com.llfbandit.record.record.format.AmrNbFormat
import com.llfbandit.record.record.format.AmrWbFormat
import com.llfbandit.record.record.format.FlacFormat
import com.llfbandit.record.record.format.Format
import com.llfbandit.record.record.format.OpusFormat
import com.llfbandit.record.record.format.PcmFormat
import com.llfbandit.record.record.format.WaveFormat
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore
import java.util.concurrent.atomic.AtomicBoolean


class RecordThread(
  private val config: RecordConfig,
  private val recorderListener: OnAudioRecordListener
) : EncoderListener {
  private var mPcmReader: PCMReader? = null
  private var mEncoder: IEncoder? = null

  // Signals whether a recording is in progress (true) or not (false).
  private val mIsRecording = AtomicBoolean(false)

  // Signals whether a recording is paused (true) or not (false).
  private val mIsPaused = AtomicBoolean(false)
  private val mIsPausedSem = Semaphore(0)
  private var mHasBeenCanceled = false

  private val mExecutorService = Executors.newSingleThreadExecutor()

  override fun onEncoderFailure(ex: Exception) {
    recorderListener.onFailure(ex)
  }

  override fun onEncoderStream(bytes: ByteArray) {
    recorderListener.onAudioChunk(bytes)
  }

  fun isRecording(): Boolean {
    return mEncoder != null && mIsRecording.get()
  }

  fun isPaused(): Boolean {
    return mEncoder != null && mIsPaused.get()
  }

  fun pauseRecording() {
    if (isRecording()) {
      pauseState()
    }
  }

  fun resumeRecording() {
    if (isPaused()) {
      recordState()
    }
  }

  fun stopRecording() {
    if (isRecording()) {
      mIsRecording.set(false)
      mIsPaused.set(false)
      mIsPausedSem.release()
    }
  }

  fun cancelRecording() {
    if (isRecording()) {
      mHasBeenCanceled = true
      stopRecording()
    } else {
      Utils.deleteFile(config.path)
    }
  }

  fun getAmplitude(): Double = mPcmReader?.getAmplitude() ?: -160.0

  fun startRecording() {
    val startLatch = CountDownLatch(1)

    mExecutorService.execute {
      try {
        val format = selectFormat()
        val (encoder, adjustedFormat) = format.getEncoder(config, this)

        mPcmReader = PCMReader(config, adjustedFormat)
        mPcmReader!!.start()

        mEncoder = encoder
        mEncoder!!.startEncoding()

        recordState()

        startLatch.countDown()

        while (isRecording()) {
          if (isPaused()) {
            recorderListener.onPause()
            mIsPausedSem.acquire()
          } else {
            val buffer = mPcmReader!!.read()
            if (buffer.isNotEmpty()) {
              mEncoder!!.encode(buffer)
            }
          }
        }
      } catch (ex: Exception) {
        recorderListener.onFailure(ex)
      } finally {
        startLatch.countDown()
        stopAndRelease()
      }
    }

    startLatch.await()
  }

  private fun stopAndRelease() {
    try {
      mPcmReader?.stop()
      mPcmReader?.release()
      mPcmReader = null

      mEncoder?.stopEncoding()
      mEncoder = null

      if (mHasBeenCanceled) {
        Utils.deleteFile(config.path)
      }
    } catch (ex: Exception) {
      recorderListener.onFailure(ex)
    } finally {
      recorderListener.onStop()
    }
  }

  private fun selectFormat(): Format {
    return when (config.encoder) {
      AudioEncoder.AacLc, AudioEncoder.AacEld, AudioEncoder.AacHe -> AacFormat()
      AudioEncoder.AmrNb -> AmrNbFormat()
      AudioEncoder.AmrWb -> AmrWbFormat()
      AudioEncoder.Flac -> FlacFormat()
      AudioEncoder.Pcm16bits -> PcmFormat()
      AudioEncoder.Opus -> OpusFormat()
      AudioEncoder.Wav -> WaveFormat()
    }
  }

  private fun pauseState() {
    mIsRecording.set(true)
    mIsPaused.set(true)

    // pause event is fired in recording loop
  }

  private fun recordState() {
    mIsRecording.set(true)
    mIsPaused.set(false)

    mIsPausedSem.release()

    recorderListener.onRecord()
  }
}