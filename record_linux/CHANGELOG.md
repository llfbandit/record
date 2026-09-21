## 2.1.2
* fix: Drain parecord/ffmpeg output pipes to prevent stalled recordings and hanging `stop()`.
* fix: Broken device selection.

## 2.1.1
* fix: don't close ffmpeg stdin while pipe is bound.

## 2.1.0
* feat: Improve InputDevice description with sample rates.
* fix: codec/device caps and surface `onConfigChanged` to dart side.
* fix: Missing await on _startFfmpegWithAmplitudeMonitoring.
* fix: Ensures EOF reaches ffmpeg.
* fix: `dispose()` closes the state stream before calling `stop()`.
* fix: `_parseInputDevices` truncates device names containing colons.
* fix: pcm16bits support for file output.
* fix: Code style improvements.

## 2.0.0
* chore: Updates minimum supported SDK version to Flutter 3.44/Dart 3.12.

## 1.3.1
* fix: Overriding the locale of `pactl` command for consistent parsing.

## 1.3.0
* feat: Add `request` parameter to `hasPermission()` method to check permission status without requesting.

## 1.2.1
* fix: Bad state: StreamSink is bound to a stream error when stopping recording.

## 1.2.0
* feat: Implement amplitude (dBFS)

## 1.1.1
* fix: nullify state stream controller when disposing and make it as broadcast controller.

## 1.1.0
* feat: Allow pcm16bits streaming.
* chore: code cleanup.

## 1.0.0
* fix: use PulseAudio recorder (parecord) instead of fmedia as library.

## 0.7.2
* fix: fmedia invalid pipe path which may lead to inaccessible audio file.

## 0.7.1
* chore: Remove channels & sample rates on InputDevice.

## 0.7.0
* fix: Allow recording with 5.1 & 7.1 channels (respectively 6 & 8).

## 0.6.0
* chore: Update platform interface.

## 0.5.0
* chore: Change signature of `start` method.
* feat: Add multiple instance support.
* feat: Add `startStream` method.
* feat: Add `cancel` method.

## 0.4.1
- fix: Read all output streams to not leak system resources.

## 0.4.0
- fix: Read all output streams to not leak system resources.
- chore: fmedia is no more included with the package until a viable solution is found.
  - You must install it separately and/or distribute it accordingly.
  - This has been done to fix current build issues.

## 0.3.4
- fix: fmedia executable lookup.
- core: Update fmedia to version 1.29.1.

## 0.3.3
- fix: Flac recording.
- fix: ACC HE (v2) is now listed as supported.
- feat: `onStateChanged()` implementation.
- core: Add debug print when recording to know if fmedia failed.

## 0.3.2
- fix: CMakeLists bundled libraries.

## 0.3.1
- fix: shared assets between platforms, fmedia binaries are now in platform folder.

## 0.3.0
- fix: shared assets between platforms, fmedia binaries are now in platform folder.

## 0.2.0
- feat: Add input devices listing.
- feat: Add number of channels.
- core: Update fmedia to version 1.28.

## 0.1.0
* core: Initial release