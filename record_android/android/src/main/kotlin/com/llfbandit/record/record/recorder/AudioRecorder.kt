package com.llfbandit.record.record.recorder

import android.content.Context
import android.os.Handler
import android.util.Log
import com.llfbandit.record.record.model.AudioInterruption
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.model.RecordState
import com.llfbandit.record.record.audio_manager.AudioSessionManager
import com.llfbandit.record.record.stream.RecorderRecordStreamHandler
import com.llfbandit.record.record.stream.RecorderStateStreamHandler


interface OnAudioRecordListener {
  fun onRecord()
  fun onPause()
  fun onStop()
  fun onFailure(ex: Exception)
  fun onAudioChunk(chunk: ByteArray)
}

class AudioRecorder(
  private val recorderStateStreamHandler: RecorderStateStreamHandler,
  private val recorderRecordStreamHandler: RecorderRecordStreamHandler,
  appContext: Context,
  handler: Handler,
) : IRecorder, OnAudioRecordListener {
  companion object {
    private val TAG = AudioRecorder::class.java.simpleName
    private const val DEFAULT_AMPLITUDE = -160.0
  }

  private var recorderThread: RecordThread? = null
  private var maxAmplitude = DEFAULT_AMPLITUDE
  private var config: RecordConfig? = null
  private var stopCb: ((path: String?) -> Unit)? = null

  private val audioSession = AudioSessionManager(
    appContext,
    handler,
    onFocusLoss = { recorderThread?.pauseRecording() },
    onFocusGain = { interruption ->
      if (interruption == AudioInterruption.PAUSE_RESUME) recorderThread?.resumeRecording()
    }
  )

  init {
    audioSession.save()
  }

  @Throws(Exception::class)
  override fun start(config: RecordConfig) {
    this.config = config
    recorderThread = RecordThread(config, this)
    recorderThread!!.startRecording()
    audioSession.apply(config, requestFocus = true)
  }

  override fun stop(stopCb: ((path: String?) -> Unit)?) {
    this.stopCb = stopCb
    if (recorderThread != null) {
      if (recorderThread?.isRecording() == true) {
        recorderThread?.stopRecording()
      }
    } else {
      onStop()
    }
  }

  override fun cancel() {
    recorderThread?.cancelRecording()
  }

  override fun pause() {
    if (isRecording) {
      audioSession.restore(config)
    }
    recorderThread?.pauseRecording()
  }

  override fun resume() {
    if (isPaused) {
      config?.let { audioSession.apply(it, requestFocus = false) }
    }
    recorderThread?.resumeRecording()
  }

  override val isRecording: Boolean
    get() = recorderThread?.isRecording() == true

  override val isPaused: Boolean
    get() = recorderThread?.isPaused() == true

  override fun getAmplitude(): List<Double> {
    val amplitude = recorderThread?.getAmplitude() ?: DEFAULT_AMPLITUDE
    if (amplitude > maxAmplitude) maxAmplitude = amplitude
    return listOf(amplitude, maxAmplitude)
  }

  override fun dispose() {
    stop(null)
  }

  override fun onRecord() {
    recorderStateStreamHandler.sendStateEvent(RecordState.RECORD)
  }

  override fun onPause() {
    recorderStateStreamHandler.sendStateEvent(RecordState.PAUSE)
  }

  override fun onStop() {
    recorderThread = null
    audioSession.restore(config)
    stopCb?.invoke(config?.path)
    stopCb = null
    recorderStateStreamHandler.sendStateEvent(RecordState.STOP)
    maxAmplitude = DEFAULT_AMPLITUDE
  }

  override fun onFailure(ex: Exception) {
    Log.e(TAG, ex.message, ex)
    recorderStateStreamHandler.sendStateErrorEvent(ex)
    recorderRecordStreamHandler.sendErrorEvent(ex)
  }

  override fun onAudioChunk(chunk: ByteArray) {
    recorderRecordStreamHandler.sendRecordChunkEvent(chunk)
  }
}
