package com.llfbandit.record;

import androidx.annotation.Nullable;

import java.io.File;

public class Utils {
  private Utils() {
  }

  public static <T> T firstNonNull(@Nullable T first, @Nullable T second) {
    return first != null ? first : checkNotNull(second);
  }

  public static <T> T checkNotNull(T reference) {
    if (reference == null) {
      throw new NullPointerException();
    }
    return reference;
  }

  public static void deleteFile(String path) {
    if (path == null) return;

    try {
      File file = new File(path);

      if (file.exists()) {
        //noinspection ResultOfMethodCallIgnored
        file.delete();
      }
    } catch (SecurityException e) {
      // Ignored
    }
  }
}
