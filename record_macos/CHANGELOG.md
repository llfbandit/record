## Upcoming
* feat: Add `request` parameter to `hasPermission()` method to check permission status without requesting.

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