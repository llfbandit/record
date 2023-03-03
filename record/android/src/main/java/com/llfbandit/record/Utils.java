package com.llfbandit.record;

import androidx.annotation.Nullable;

import java.io.File;
import java.io.IOException;

public class Utils {
  private Utils() {}

  public static String genTempFileName(String encoder) throws IOException {
    String suffix = ".m4a";

    if (encoder != null) {
      switch (encoder) {
        case "amrNb":
        case "amrWb":
          suffix = ".amr";
          break;
        case "flac":
          suffix = ".flac";
          break;
        case "opus":
          suffix = ".opus";
          break;
        case "vorbisOgg":
          suffix = ".ogg";
          break;
        case "pcm8bit":
        case "pcm16bit":
          suffix = ".pcm";
          break;
        case "wav":
          suffix = ".wav";
          break;
        case "aacLc":
        case "aacEld":
        case "aacHe":
        default:
          suffix = ".m4a";
          break;
      }
    }

    return File
        .createTempFile("audio", suffix)
        .getPath();
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
}
