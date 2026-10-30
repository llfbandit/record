package com.llfbandit.record.record.util

import java.io.File

object Utils {
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
