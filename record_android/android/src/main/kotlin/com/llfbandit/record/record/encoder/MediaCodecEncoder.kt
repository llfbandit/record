package com.llfbandit.record.record.encoder

import android.annotation.TargetApi
import android.media.MediaCodec
import android.media.MediaCodec.CodecException
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import com.llfbandit.record.record.container.IContainerWriter

class MediaCodecEncoder(
    mediaFormat: MediaFormat,
    private val listener: EncoderListener,
    private val container: IContainerWriter,
) : IEncoder, MediaCodec.Callback() {

    private val codec = createCodec(mediaFormat)
    private var trackIndex = -1
    private var recordStopped: Boolean = false

    override fun start() {
        codec.setCallback(this)
        codec.start()
    }

    override fun stop() {
        recordStopped = true
    }

    override fun release() {
        codec.release()
        container.release()
    }

    @TargetApi(Build.VERSION_CODES.Q)
    private fun findCodecForFormat(format: MediaFormat): String? {
        val mime = format.getString(MediaFormat.KEY_MIME)
        val codecs = MediaCodecList(MediaCodecList.REGULAR_CODECS)

        for (info in codecs.codecInfos.sortedBy { !it.canonicalName.startsWith("c2.android") }) {
            if (!info.isEncoder) {
                continue
            }
            try {
                val caps = info.getCapabilitiesForType(mime)
                if (caps != null && caps.isFormatSupported(format)) {
                    return info.canonicalName
                }
            } catch (e: IllegalArgumentException) {
                // type is not supported
            }
        }
        return null
    }

    private fun createCodec(mediaFormat: MediaFormat): MediaCodec {
        val encoder = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).findEncoderForFormat(mediaFormat)
        } else {
            findCodecForFormat(mediaFormat)
        }

        encoder ?: throw Exception("No encoder found for $mediaFormat")

        var mediaCodec: MediaCodec? = null
        try {
            mediaCodec = MediaCodec.createByCodecName(encoder)
            mediaCodec.configure(mediaFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            return mediaCodec
        } catch (e: Exception) {
            mediaCodec?.release()
            throw e
        }
    }

    private fun internalStop() {
        codec.stop()

        listener.onEncoderStop()
    }

    //////////////////////////////////////////////////////////
    // MediaCodec.Callback
    //////////////////////////////////////////////////////////
    override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
        try {
            trackIndex = container.addTrack(format)
            container.start()
        } catch (e: Exception) {
            listener.onEncoderFailure(e)
            internalStop()
        }
    }

    override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {
        try {
            val byteBuffer = codec.getInputBuffer(index) ?: return
            val resultBytes = listener.onEncoderDataNeeded(byteBuffer)
            val flags = if (recordStopped) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0

            codec.queueInputBuffer(index, 0, resultBytes, 0, flags)
        } catch (e: Exception) {
            listener.onEncoderFailure(e)
            internalStop()
        }
    }

    override fun onOutputBufferAvailable(
        codec: MediaCodec,
        index: Int,
        info: MediaCodec.BufferInfo
    ) {
        try {
            val byteBuffer = codec.getOutputBuffer(index)
            if (byteBuffer != null) {
                if (!container.isStream()) {
                    container.writeSampleData(trackIndex, byteBuffer, info)
                } else {
                    listener.onEncoderStream(container.writeStream(trackIndex, byteBuffer, info))
                }
            }
            codec.releaseOutputBuffer(index, false)
            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                internalStop()
            }
        } catch (e: Exception) {
            listener.onEncoderFailure(e)
            internalStop()
        }
    }

    override fun onError(codec: MediaCodec, e: CodecException) {
        listener.onEncoderFailure(e)
        internalStop()
    }
}