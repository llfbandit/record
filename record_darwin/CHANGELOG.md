## 1.0.1
* chore: Reworked again implementations to be closer to previous versions:
    - iOS Simulator is now usable again.
    - streaming is now done via AudioEngine.
* fix: Wrong channel bounds (Thanks to @EvertonMJunior)

## 1.0.0
* chore: Initial stable release.

## 1.0.0-beta.2+4
* fix: reflect stop changes on iOS code.

## 1.0.0-beta.2+3
* fix: stop method should return path only after completed recording.
* fix: Send stream event on main thread.

## 1.0.0-beta.2+2
* fix: PCM custom settings.
* fix: PCM big endian missing key.

## 1.0.0-beta.2+1
* fix: stop procedure.

## 1.0.0-beta.2
* chore: Update platform interface.
* fix(iOS): start AVCaptureSession from background thread.
* fix: PCM stream now takes accurate num channels from current connection.
* feat: Allow new method to retrieve audio data from macOS 10.15 & iOS 13.

## 1.0.0-beta.1+4
* fix: Just don't publish it from Windows.

## 1.0.0-beta.1+3
* fix: Use hard link instead of soft.

## 1.0.0-beta.1+2
* fix: RecordPlugin.h is now plain file. Symbolic link seems to not be resolved for headers?

## 1.0.0-beta.1+1
* fix: podspec is now plain file. Symbolic link seems to not be resolved for podspec.

## 1.0.0-beta.1
* core: Initial release