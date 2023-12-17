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