package com.llfbandit.record

import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.RejectedExecutionException

internal class RecorderCallQueue(
  threadName: String,
  private val executor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
    Thread(runnable, threadName).apply { isDaemon = true }
  }
) {
  private val executing = ThreadLocal<Boolean>()
  private var closed = false
  private var closeFuture: Future<*>? = null

  @Synchronized
  fun execute(call: () -> Unit): Boolean {
    if (closed) return false

    return try {
      executor.execute(wrap(call))
      true
    } catch (_: RejectedExecutionException) {
      false
    }
  }

  fun executeOrRun(call: () -> Unit): Boolean {
    if (executing.get() == true) {
      call()
      return true
    }

    return execute(call)
  }

  @Synchronized
  fun close(cleanup: () -> Unit): Future<*> {
    closeFuture?.let { return it }
    closed = true

    val cleanupFuture = executor.submit(wrap(cleanup))
    closeFuture = cleanupFuture
    executor.shutdown()
    return cleanupFuture
  }

  private fun wrap(call: () -> Unit) = Runnable {
    executing.set(true)
    try {
      call()
    } finally {
      executing.remove()
    }
  }
}
