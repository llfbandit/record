package com.llfbandit.record

import java.io.File

object Utils {
  fun <T> firstNonNull(first: T?, second: T): T {
    return first ?: checkNotNull<T>(second)
  }

  fun <T> checkNotNull(reference: T?): T {
    if (reference == null) {
      throw NullPointerException()
    }
    return reference
  }

  fun deleteFile(path: String?) {
    if (path == null) return

    try {
      val file = File(path)

      if (file.exists()) {
        file.delete()
      }
    } catch (_: SecurityException) {
      // Ignored
    }
  }
}
