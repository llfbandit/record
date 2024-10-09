package com.llfbandit.record.record.recorder

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import com.llfbandit.record.Utils
import com.llfbandit.record.record.AudioEncoder
import com.llfbandit.record.record.RecordConfig
import com.llfbandit.record.record.RecordState
import com.llfbandit.record.record.stream.RecorderStateStreamHandler
import java.io.IOException
import kotlin.math.log10

class MediaRecorder(
    private val context: Context,
    private val recorderStateStreamHandler: RecorderStateStreamHandler,
) : IRecorder {
    companion object {
        private val TAG = MediaRecorder::class.java.simpleName
    }

    // Signals whether a recording is in progress (true) or not (false).
    private var mIsRecording = false

    // Signals whether a recording is paused (true) or not (false).
    private var mIsPaused = false

    private var mRecorder: MediaRecorder? = null

    // Amplitude
    private var mMaxAmplitude = -160.0

    // Recording config
    private var mConfig: RecordConfig? = null

    @Throws(Exception::class)
    override fun start(config: RecordConfig) {
        stopRecording()

        val recorder = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            @Suppress("DEPRECATION")
            MediaRecorder()
        } else {
            MediaRecorder(context)
        }

        recorder.setAudioSource(config.audioSource)
        recorder.setAudioEncodingBitRate(config.bitRate)
        recorder.setAudioSamplingRate(config.sampleRate)
        recorder.setAudioChannels(2.coerceAtMost(1.coerceAtLeast(config.numChannels)))
        recorder.setOutputFormat(getOutputFormat(config.encoder))
        // must be set after output format
        recorder.setAudioEncoder(getEncoder(config.encoder))
        recorder.setOutputFile(config.path)

        try {
            recorder.prepare()
            recorder.start()

            mConfig = config
            mRecorder = recorder

            updateState(RecordState.RECORD)
        } catch (e: IOException) {
            recorder.release()
            throw Exception(e)
        } catch (e: IllegalStateException) {
            recorder.release()
            throw Exception(e)
        }
    }

    override fun stop(stopCb: ((path: String?) -> Unit)?) {
        stopRecording()
        stopCb?.invoke(mConfig?.path)
    }

    override fun cancel() {
        stopRecording()
        Utils.deleteFile(mConfig?.path)
    }

    @RequiresApi(api = Build.VERSION_CODES.N)
    override fun pause() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            pauseRecording()
        }
    }

    @RequiresApi(api = Build.VERSION_CODES.N)
    override fun resume() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            resumeRecording()
        }
    }

    override val isRecording: Boolean
        get() = mIsRecording
    override val isPaused: Boolean
        get() = mIsPaused

    override fun getAmplitude(): List<Double> {
        var current = -160.0

        if (mIsRecording) {
            current = 20 * log10(mRecorder!!.maxAmplitude / 32768.0)

            if (current > mMaxAmplitude) {
                mMaxAmplitude = current
            }
        }

        val amps: MutableList<Double> = ArrayList()
        amps.add(current)
        amps.add(mMaxAmplitude)
        return amps
    }

    override fun dispose() {
        stopRecording()
    }

    private fun stopRecording() {
        if (mRecorder != null) {
            try {
                if (mIsRecording || mIsPaused) {
                    mRecorder!!.stop()
                }
            } catch (ex: RuntimeException) {
                // Mute this exception since 'isRecording' can't be 100% sure
            } finally {
                mRecorder!!.reset()
                mRecorder!!.release()
                mRecorder = null
            }
        }

        updateState(RecordState.STOP)
        mMaxAmplitude = -160.0
    }

    @RequiresApi(api = Build.VERSION_CODES.N)
    private fun pauseRecording() {
        if (mRecorder != null) {
            try {
                if (mIsRecording) {
                    mRecorder!!.pause()
                    updateState(RecordState.PAUSE)
                }
            } catch (ex: IllegalStateException) {
                Log.d(
                    TAG,
                    """
                        Did you call pause() before before start() or after stop()?
                        ${ex.message}
                        """.trimIndent()
                )
            }
        }
    }

    @RequiresApi(api = Build.VERSION_CODES.N)
    private fun resumeRecording() {
        if (mRecorder != null) {
            try {
                if (mIsPaused) {
                    mRecorder!!.resume()
                    updateState(RecordState.RECORD)
                }
            } catch (ex: IllegalStateException) {
                Log.d(
                    TAG,
                    """
                        Did you call resume() before before start() or after stop()?
                        ${ex.message}
                        """.trimIndent()
                )
            }
        }
    }

    private fun updateState(state: RecordState) {
        when (state) {
            RecordState.PAUSE -> {
                mIsRecording = true
                mIsPaused = true
                recorderStateStreamHandler.sendStateEvent(RecordState.PAUSE.id)
            }

            RecordState.RECORD -> {
                mIsRecording = true
                mIsPaused = false
                recorderStateStreamHandler.sendStateEvent(RecordState.RECORD.id)
            }

            RecordState.STOP -> {
                mIsRecording = false
                mIsPaused = false
                recorderStateStreamHandler.sendStateEvent(RecordState.STOP.id)
            }
        }
    }

    private fun getOutputFormat(encoder: String): Int {
        return when (encoder) {
            AudioEncoder.aacLc, AudioEncoder.aacEld, AudioEncoder.aacHe -> MediaRecorder.OutputFormat.MPEG_4
            AudioEncoder.amrNb, AudioEncoder.amrWb -> MediaRecorder.OutputFormat.THREE_GPP
            AudioEncoder.opus -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    MediaRecorder.OutputFormat.OGG
                } else {
                    MediaRecorder.OutputFormat.MPEG_4
                }
            }

            else -> MediaRecorder.OutputFormat.DEFAULT
        }
    }

    // https://developer.android.com/reference/android/media/MediaRecorder.AudioEncoder
    private fun getEncoder(encoder: String): Int {
        return when (encoder) {
            AudioEncoder.aacLc -> MediaRecorder.AudioEncoder.AAC
            AudioEncoder.aacEld -> MediaRecorder.AudioEncoder.AAC_ELD
            AudioEncoder.aacHe -> MediaRecorder.AudioEncoder.HE_AAC
            AudioEncoder.amrNb -> MediaRecorder.AudioEncoder.AMR_NB
            AudioEncoder.amrWb -> MediaRecorder.AudioEncoder.AMR_WB
            AudioEncoder.opus -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    MediaRecorder.AudioEncoder.OPUS
                } else {
                    Log.d(TAG, "Falling back to AAC LC")
                    MediaRecorder.AudioEncoder.AAC
                }
            }

            else -> {
                Log.d(TAG, "Falling back to AAC LC")
                MediaRecorder.AudioEncoder.AAC
            }
        }
    }
}
