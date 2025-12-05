## Upcoming
* feat: Add `request` parameter to `hasPermission()` method to check permission status without requesting.

## 1.4.5
* fix: WAVE header for files larger than 2GB.

## 1.4.4
* fix: crash when notify a notification with a background service on devices below Android 8.0.
* fix: Update build config.

## 1.4.3
* fix: Missing notification channel when using AndroidService.

## 1.4.2
* fix: Flac recording failure by isolating CSD frame skipping.

## 1.4.1
* fix: Calling stop never ends when not recording.
* fix: Update max amplitude when streaming.
* fix: AudioRecord calls the wrong method to read shorts.

## 1.4.0
* feat: Add AudioInterruptionMode to `RecordConfig`.
* feat: Add stream buffer size option.
* feat: Allow background recording.
* fix: malformed AAC on Android.

## 1.3.3
* fix: Gradle compile SDK to 34.

## 1.3.2
* fix: Pause state accuracy.
* fix: AAC ADTS streaming.
* feat: Add `audioManagerMode` and `speakerphone` options to mitigate echo cancellation issues with specific devices. (Thanks to @keyur2maru for the original PR)

## 1.3.1
* fix: Stop does not complete when called immediately after startStream.
* fix: No static method `addLast`.

## 1.3.0
* feat: Add audio source config.
* feat: Add manageBluetooth (SCO) option.
* fix: Audio source is now AndroidAudioSource.defaultSource (without any effect pre-processor in theory).
* fix: Recording not working when starting from an Android ForegroundService.
* fix: MPEG4 container is not returned when requesting AudioEncoder.opus for MediaRecorder (legacy).
* fix: Race condition when calling stop.
* chore: Add debug log when effect is not available while requested.

## 1.2.6
* fix: Improve amplitude computation.
* fix: java.lang.IllegalStateException: Failed to stop the muxer.
* fix: Exception raised on bluetooth receiver unregistration.
* chore: Upgrade to latest AGP.

## 1.2.5
* fix: Applying effects.
* fix: Race condition leading to exception when releasing codec & muxer.

## 1.2.4
* fix: Revert to Java 8.

## 1.2.3
* fix: Revert AGP v8 setup to latest v7.
* fix: Don't start bluetooth SCO when asking for another device type.

## 1.2.2
* fix: Threading issues. Model is now more robust and overall performance is much better.
* fix: Recording on older Android devices ..., 8, 9.
* fix: Recording on slow devices (e.g. writing on external SD cards, ...).
* fix: Audio duration detection should be less a problem now.
* chore: minSDK is now 23 (Android 6), targetSDK is now 34.
* chore: code cleanup and adjustment from new minSDK.

## 1.2.1
* fix: Stopping stream recording throws ExceptionInterruptedException.

## 1.2.0
* feat: Re-introduced native MediaRecorder. Set `RecordConfig.androidConfig.useLegacy` to `true`. This comes with limitations compared to advanced recorder.
* feat: Advanced AudioRecorder will try to adjust given configuration if unsupported or out of range (sample rate, bitrate and channel count).
  * Those two features should help for older devices, bad vendor implementations or misusage of configuration values.
* feat: ability to mute all audio streams when recording. The settings are restored when the recording is stopped.
  * Notice: streams will stay at current state on pause/resume.

## 1.1.0
* fix: Properly close container when recording is stopped.
* fix: num channels & sample rate are not applied in AAC format.
* feat: Add device listing/selection (selection is not guaranteed but preferred only...).
* feat: Add bluetooth SCO auto linking (i.e. for telephony device like headset/earbuds).
  * Recording quality is limited.
  * You must add "MODIFY_AUDIO_SETTINGS" permission to allow recording from those devices. See README.md.

## 1.0.4
* fix: AAC duration can not be obtained.

## 1.0.3
* fix: Stop method returns before recording being actually finished.
* fix: Changing config is not taken into account when reusing same instance.

## 1.0.2
* chore: Allow AGP 8 and beyond while being backward compatible with older AGP versions.

## 1.0.1
* chore: Allow AGP 8 and beyond while being backward compatible with older AGP versions.

## 1.0.0
* chore: Initial stable release.

## 1.0.0-beta.2
* chore: Cleanup/improve some code.

## 1.0.0-beta.1+1
* fix: PassthroughEncoder does not check if the container is configured with stream behaviour.

## 1.0.0-beta.1
* chore: Initial release