## 2.3.0
* refactor: redirect recorder control onto one background thread.

## 2.2.3
* fix: Corrupted WAV file size fields.

## 2.2.2
* fix: non-ascii char in comment preventing compilation when using simplified shinese codepage.

## 2.2.1
* fix: restore record event handler after stream start.

## 2.2.0
* feat: Add AAC-ADTS streaming.
* chore: Code improvements / various fixes.

## 2.1.0
* feat: Improve InputDevice description with sample rates and type.
* feat: warmup codec caps when creating Recoder.
* fix: codec/device caps and surface `onConfigChanged` to dart side.
* fix: timestamps after pause/resume cycling. resume state event now fired at right time.
* fix: BinaryMessenger not shared.
* fix: Correct HR result from ListInputDevices.
* fix: Race condition on dispose/stop.
* fix: Ensures that channels are only added if Recorder instance is created.
* fix: Memory leak on ListInputDevices.
* fix: Wrong amplitude.
* fix: Potential crash when streaming.
* fix: Only set config if EndRecording succeeded.
* fix: Let MFTEnumEx check if AMR_WB is available as encoder.
* fix: Reshape project with better separation of concerns.

## 2.0.0
* chore: Updates minimum supported SDK version to Flutter 3.44/Dart 3.12.

## 1.0.7
* fix: Crashes (on Flutter 3.35.1 only ?)

## 1.0.6
* fix: Attempt to fix crash when recording on w10.

## 1.0.5
* fix: Send messages on main thread (workaround).
* fix: Automatically remove file when no audio has been written.

## 1.0.4
* fix: Process path as wide string (UTF-16).

## 1.0.3
* fix: Crash when starting the recording when the writer can't be created.

## 1.0.2
* fix: Quick creation/start/stop sequence resulting in a crash.

## 1.0.1
* fix: UTF-16 to UTF-8 could fail.

## 1.0.0
* chore: Initial stable release.

## 1.0.0-beta.2+1
* fix: regression on WAV & PCM recording.
* fix: UTF-16 to UTF-8 could fail.

## 1.0.0-beta.2
* chore: Cleanup/improve some code.

## 1.0.0-beta.1+1
* fix: Error messages are not readable from dart side.

## 1.0.0-beta.1
* chore: Windows now uses MediaFoundation shipped with all 10 & 11 versions
* chore: Change signature of `start` method.
* feat: Add multiple instance support.
* feat: Add `startStream` method.
* feat: Add `cancel` method.
* feat: Add amplitude.

## 0.7.1
- fix: Read all output streams to not leak system resources.

## 0.7.0
- fix: Read all output streams to not leak system resources.
- chore: Update fmedia to version 1.29.1. 

## 0.6.2
- fix: Flac recording.
- fix: ACC HE (v2) is now listed as supported.
- feat: `onStateChanged()` implementation.
- core: Add debug print when recording to know if fmedia failed.

## 0.6.1
- fix: CMakeLists bundled libraries.

## 0.6.0
- fix: shared assets between platforms, fmedia binaries are now in platform folder.

## 0.5.0
- feat: Add input devices listing.
- feat: Add number of channels.
- core: Update fmedia to version 1.28.

## 0.4.3
* fix: Better handling of fmedia process (start/pause/resume/stop start/stop again and again).

## 0.4.2
* fix: Unreachable MethodChannel.

## 0.4.1
* fix: Remove CMakeLists.txt.

## 0.4.0
* feat: Replace SFML by fmedia.

## 0.3.0
* fix: Cmake build fix by using FetchContent (still WIP).

## 0.2.0
* core: Provide also debug DLL to not crash apps. Need to be fixed.

## 0.1.0
* core: Initial release