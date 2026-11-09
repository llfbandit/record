package com.llfbandit.record.record.format

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.util.Range
import com.llfbandit.record.record.model.RecordConfig
import com.llfbandit.record.record.util.DeviceUtils
import com.llfbandit.record.record.encoder.IEncoder
import com.llfbandit.record.record.encoder.MediaCodecEncoder
import com.llfbandit.record.record.encoder.PassthroughEncoder

data class EncoderSetup(val encoder: IEncoder, val mediaFormat: MediaFormat, val config: RecordConfig)

internal object FormatCodecSelector {
  fun findCodec(
    format: Format,
    config: RecordConfig,
    onChunk: (ByteArray) -> Unit,
  ): EncoderSetup {

    // Clamp config to device caps.
    val clamped = adjustToDeviceCapabilities(config)

    // Load MediaFormat from given config and adjust it from codec caps.
    val mediaFormat = format.getMediaFormat(clamped)

    if (format.mimeTypeAudio == MediaFormat.MIMETYPE_AUDIO_RAW) {
      val negotiated = negotiated(clamped, mediaFormat)
      return EncoderSetup(PassthroughEncoder(negotiated, format, mediaFormat, onChunk), mediaFormat, negotiated)
    }

    val codecs = MediaCodecList(MediaCodecList.REGULAR_CODECS)

    for (info in codecs.codecInfos) {
      if (!info.isEncoder) continue

      try {
        val caps = info.getCapabilitiesForType(format.mimeTypeAudio)
        if (caps != null && adjustToCapabilities(caps, mediaFormat)) {
          val negotiated = negotiated(clamped, mediaFormat)
          return EncoderSetup(MediaCodecEncoder(negotiated, format, mediaFormat, onChunk, info.name), mediaFormat, negotiated)
        }
      } catch (_: IllegalArgumentException) {
        // type not supported by this codec
      }
    }

    throw Exception("No codec found for given config $mediaFormat. You should try with other values.")
  }

  /**
   * Attempts to adjust [mediaFormat] to fit within device and codec [caps].
   * Returns true if the format is supported after adjustment.
   */
  private fun adjustToCapabilities(
    caps: MediaCodecInfo.CodecCapabilities,
    mediaFormat: MediaFormat
  ): Boolean {
    var supported = caps.isFormatSupported(mediaFormat)

    if (!supported) {
      val audioCapabilities = caps.audioCapabilities

      if (audioCapabilities != null) {
        mediaFormat.setInteger(
          MediaFormat.KEY_BIT_RATE,
          checkBounds(audioCapabilities.bitrateRange, mediaFormat.getInteger(MediaFormat.KEY_BIT_RATE))
        )
        if (audioCapabilities.supportedSampleRates != null) {
          mediaFormat.setInteger(
            MediaFormat.KEY_SAMPLE_RATE,
            nearestValue(audioCapabilities.supportedSampleRates, mediaFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE))
          )
        }
        mediaFormat.setInteger(
          MediaFormat.KEY_CHANNEL_COUNT,
          checkBounds(Range(1, audioCapabilities.maxInputChannelCount), mediaFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT))
        )
      }

      supported = caps.isFormatSupported(mediaFormat)
    }

    return supported
  }

  private fun adjustToDeviceCapabilities(config: RecordConfig): RecordConfig {
    val device = config.device ?: DeviceUtils.getDefaultInputDevice() ?: return config

    // PCMReader only supports mono or stereo; ignore any device channel counts above 2.
    val deviceChannelCounts = device.channelCounts.filter { c -> c <= 2 }.toIntArray()
    if (deviceChannelCounts.isEmpty()) return config
    return config.copy(numChannels = nearestValue(deviceChannelCounts, config.numChannels))
  }

  private fun negotiated(config: RecordConfig, mediaFormat: MediaFormat) = config.copy(
    sampleRate = mediaFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE),
    numChannels = mediaFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT),
    bitRate = if (mediaFormat.containsKey(MediaFormat.KEY_BIT_RATE)) {
      mediaFormat.getInteger(MediaFormat.KEY_BIT_RATE)
    } else {
      config.bitRate
    },
  )

  private fun checkBounds(range: Range<Int>, value: Int): Int {
    if (range.lower > value) return range.lower
    if (range.upper < value) return range.upper
    return value
  }
}
