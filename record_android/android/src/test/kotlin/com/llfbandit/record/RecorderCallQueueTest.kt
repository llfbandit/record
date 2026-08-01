package com.llfbandit.record

import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class RecorderCallQueueTest {
  @Test
  fun executeReturnsWhileBlockedCallRuns() {
    val executor = newExecutor()
    val queue = RecorderCallQueue("unused", executor)
    val firstStarted = CountDownLatch(1)
    val releaseFirst = CountDownLatch(1)
    val secondRan = CountDownLatch(1)

    try {
      assertTrue(queue.execute {
        firstStarted.countDown()
        releaseFirst.await()
      })
      assertTrue(firstStarted.await(TIMEOUT_SECONDS, TimeUnit.SECONDS))

      assertTrue(queue.execute { secondRan.countDown() })
      assertEquals(1L, secondRan.count)
    } finally {
      releaseFirst.countDown()
      queue.close {}.get(TIMEOUT_SECONDS, TimeUnit.SECONDS)
    }

    assertTrue(secondRan.await(TIMEOUT_SECONDS, TimeUnit.SECONDS))
  }

  @Test
  fun callsAndCleanupRunInOrder() {
    val executor = newExecutor()
    val queue = RecorderCallQueue("unused", executor)
    val calls = CopyOnWriteArrayList<Int>()

    assertTrue(queue.execute { calls.add(1) })
    assertTrue(queue.execute { calls.add(2) })
    assertTrue(queue.execute { calls.add(3) })

    queue.close { calls.add(4) }.get(TIMEOUT_SECONDS, TimeUnit.SECONDS)

    assertEquals(listOf(1, 2, 3, 4), calls)
    assertTrue(executor.awaitTermination(TIMEOUT_SECONDS, TimeUnit.SECONDS))
  }

  @Test
  fun closeIsIdempotentAndRejectsLaterCalls() {
    val executor = newExecutor()
    val queue = RecorderCallQueue("unused", executor)
    val cleanupCalls = AtomicInteger()

    val firstClose = queue.close { cleanupCalls.incrementAndGet() }
    val secondClose = queue.close { cleanupCalls.incrementAndGet() }

    assertSame(firstClose, secondClose)
    firstClose.get(TIMEOUT_SECONDS, TimeUnit.SECONDS)
    assertEquals(1, cleanupCalls.get())
    assertFalse(queue.execute {})
    assertFalse(queue.executeOrRun {})
    assertTrue(executor.awaitTermination(TIMEOUT_SECONDS, TimeUnit.SECONDS))
  }

  @Test
  fun executeOrRunKeepsNestedContinuationInPlace() {
    val executor = newExecutor()
    val queue = RecorderCallQueue("unused", executor)
    val calls = CopyOnWriteArrayList<Int>()

    assertTrue(queue.execute {
      calls.add(1)
      assertTrue(queue.executeOrRun { calls.add(2) })
      calls.add(3)
    })
    queue.close { calls.add(4) }.get(TIMEOUT_SECONDS, TimeUnit.SECONDS)

    assertEquals(listOf(1, 2, 3, 4), calls)
  }

  private fun newExecutor() = Executors.newSingleThreadExecutor { runnable ->
    Thread(runnable, "RecorderCallQueueTest").apply { isDaemon = true }
  }

  companion object {
    private const val TIMEOUT_SECONDS = 5L
  }
}
