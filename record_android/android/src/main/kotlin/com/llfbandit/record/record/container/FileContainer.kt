package com.llfbandit.record.record.container

import android.media.MediaCodec
import android.media.MediaFormat
import android.system.Os
import java.io.RandomAccessFile
import java.nio.ByteBuffer

abstract class FileContainer(path: String) : IContainerWriter {
  // Truncate stale bytes from an existing file.
  protected val file = RandomAccessFile(path, "rw").apply {
    try {
      setLength(0)
    } catch (e: Exception) {
      close()
      throw e
    }
  }

  protected var isStarted = false
    private set
  protected var hasTrack = false
    private set

  protected open fun onStart() {}
  protected open fun onTrack(mediaFormat: MediaFormat) {}
  protected open fun onStop() {}

  protected open fun write(byteBuffer: ByteBuffer, bufferInfo: MediaCodec.BufferInfo) {
    Os.write(file.fd, byteBuffer)
  }

  override fun start() {
    check(!isStarted) { "Container already started" }
    onStart()
    isStarted = true
  }

  private fun stop() {
    check(isStarted) { "Container not started" }
    isStarted = false
    try {
      onStop()
    } finally {
      file.close()
    }
  }

  override fun release() {
    if (isStarted) stop() else runCatching { file.close() }
  }

  override fun addTrack(mediaFormat: MediaFormat): Int {
    check(!isStarted) { "Container already started" }
    check(!hasTrack) { "Track already added" }
    onTrack(mediaFormat)
    hasTrack = true
    return 0
  }

  override fun writeSampleData(trackIndex: Int, byteBuffer: ByteBuffer, bufferInfo: MediaCodec.BufferInfo) {
    check(isStarted) { "Container not started" }
    check(hasTrack) { "No track has been added" }
    check(trackIndex == 0) { "Invalid track: $trackIndex" }
    write(byteBuffer, bufferInfo)
  }
}
