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