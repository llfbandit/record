## 1.2.2
* fix(macOS): Compilation issue.
* fix(darwin): Privacy manifests not bundled.

## 1.2.1
* Reuploaded package with correct repository config.

## 1.2.0
* feat(iOS): Add ios config with audio categories.
* feat(iOS): Add manageAudioSession option for IosRecordConfig
* fix(iOS): Cancel effects when stopping streaming.
* fix(iOS): Forward pause state when recording is interrupted.
* fix(darwin): Add privacy manifests to iOS & macOS.

## 1.1.2
* fix: Remove print on conversion error.
* fix: Exception where format.sampleRate != hwFormat.sampleRate
* feat(macOS): Support device by deviceID as well as deviceUID

## 1.1.1
* fix: Add swift version info to workaround compilation issues.
* fix(iOS): Enabling auto gain & echo cancel.

## 1.1.0
* fix(iOS): Don't interrupt recording from system alerts and never resume on others.
* feat(iOS): Allow AD2P bluetooth
* feat(macOS): Allow device selection when streaming
* feat(darwin): Enable autoGain & echoCancel when streaming

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