package com.llfbandit.record.record.format

import android.media.MediaFormat
import com.llfbandit.record.record.model.AudioEncoder
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.container.IContainerWriter
import com.llfbandit.record.record.encoder.EncoderListener

class LegacyRecorder(val outputFormat: Int, val audioEncoder: Int)

/**
 * Represents an audio format.
 * This class is responsible for creating the encoder and container for the specified format.
 * It also provides the [MediaFormat] for the encoded audio stream.
 */
sealed class Format {
  /**
   * The MIME type of the encoded audio stream inside the container.
   */
  abstract val mimeTypeAudio: String

  /**
   * Returns true if this format can produce a byte stream (path == null).
   * Subclasses that support streaming must override this.
   */
  open fun supportsStream(config: RecordConfig): Boolean = false

  /**
   * Create a [MediaFormat] representing the encoded audio with parameters matching the specified
   * input PCM audio format.
   */
  abstract fun getMediaFormat(config: RecordConfig): MediaFormat

  /** Null when MediaRecorder cannot record this format. */
  open fun legacyRecorder(config: RecordConfig): LegacyRecorder? = null

  /**
   * Create a container to write the encoded data.
   *
   * @param path The output path if the container writes to file.
   * @param mediaFormat The final negotiated [MediaFormat] for the encoded stream.
   * @param onChunk Receives the encoded bytes when there is no [path].
   */
  abstract fun createWriter(
    mediaFormat: MediaFormat,
    path: String?,
    onChunk: (ByteArray) -> Unit,
  ): IContainerWriter


  companion object {
    const val KEY_X_FRAME_SIZE_IN_BYTES = "x-frame-size-in-bytes"

    /**
     * Throws [IllegalArgumentException] if [config] requests stream mode but
     * the selected format does not support it.
     */
    fun checkStreamSupport(config: RecordConfig) {
      if (config.path == null && !selectFormat(config.encoder).supportsStream(config)) {
        throw IllegalArgumentException("Streaming is not supported for encoder '${config.encoder.value}'")
      }
    }

    /**
     * Create an encoder that produces [MediaFormat] output.
     */
    fun createEncoder(
      config: RecordConfig,
      listener: EncoderListener
    ): EncoderSetup {
      val format = selectFormat(config.encoder)
      return FormatCodecSelector.findCodec(format, config, listener)
    }

    fun selectFormat(encoder: AudioEncoder): Format {
      return when (encoder) {
        AudioEncoder.AacLc, AudioEncoder.AacEld, AudioEncoder.AacHe -> AacFormat()
        AudioEncoder.AmrNb -> AmrFormat.narrowBand()
        AudioEncoder.AmrWb -> AmrFormat.wideBand()
        AudioEncoder.Flac -> FlacFormat()
        AudioEncoder.Pcm16bits -> PcmFormat()
        AudioEncoder.Opus -> OpusFormat()
        AudioEncoder.Wav -> WaveFormat()
      }
    }
  }
}
