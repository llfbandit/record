## 2.0.1
* fix: Preserve user-specified sample rate for PCM/WAV encoders regardless of converter availability.

## 2.0.0
* chore: Completes Swift Package Manager integration.
* chore: Updates minimum supported SDK version to Flutter 3.44/Dart 3.12.

## 1.2.2
* fix: Stay away from Flutter UI thread.
* fix: SPM description.
* chore: Code cleanup.

## 1.2.1
* fix: Preserve stereo channels in stream mode.
* fix: Include external audio devices in discovery.

## 1.2.0
* feat: Add `request` parameter to `hasPermission()` method to check permission status without requesting.
* feat: Add AAC/ADTS streaming.

## 1.1.2
* fix: Use kAudioFormatMPEG4AAC_ELD instead of kAudioFormatMPEG4AAC_ELD_V2 for improved compatibility.
* fix: Fix applying audio settings when saving file on macOS (for PCM/WAV mostly)

## 1.1.1
* fix: Calling stop never ends when not recording.

## 1.1.0
* feat: Add stream buffer size option.
* fix: Fix echo cancellation (#523)

## 1.0.0
* chore: Support Swift Package Manager.
* feat: Enable `echoCancel` & `autoGain` for streaming mode.