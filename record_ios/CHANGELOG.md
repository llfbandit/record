## 2.2.0
* refactor: Rebuild recorder as capture engine + controller.
* fix: A recording paused by the user is no longer resumed when an interruption ends.
* fix: A failed start no longer leaves its interruption observer registered.
* fix: Device and encoder queries no longer need a recorder to be created first.

## 2.1.1
* fix: Throw for unsupported stream encoders.

## 2.1.0
* feat: Improve InputDevice description with type.
* fix: codec/device caps and surface `onConfigChanged` to dart side.
* fix: Don't override AVAudioSession.Category if there's no need for listing devices.
* fix: interleaved true, corrupting PCM stream data.
* fix: pause/resume consistent state.
* fix: Increases output buffer for aac encoder to prevent frame loss at high rates.
* fix: Potential crash in encodeAac.
* fix: handleStop bypassed m_recorderQueue.
* fix: Interruption observers accumulation.
* fix: audioRecorderDidFinishRecording has empty body, recorder can be stuck in .record on system error.
* fix: Race condition in AacAdtsEncoder.
* fix: ADTS fixes.
* fix: stop() called from tap callback can cause deadlock.
* fix: Potential race conditions. Reworked queue dispatching.
* fix: Reshape project with better separation of concerns.

## 2.0.0
* fix: Respect `shouldResume` system flag on audio interruption and don't stop on resume failure.
* chore: **Breaking change** Remove `manageAudioSession` deprecated config property.
* chore: Completes Swift Package Manager integration.
* chore: Updates minimum supported SDK version to Flutter 3.44/Dart 3.12.

## 1.2.1
* feat: Add `allowHapticsAndSystemSoundsDuringRecording` iOS option.
* fix: Fuzzy events firing for recording states.
* fix: AVAudioPCMBuffer frame capacity calculation.
* fix: Stay away from Flutter UI thread.
* fix: SPM description.
* chore: Code cleanup.
* chore: Update example project.

## 1.2.0
* feat: Add `request` parameter to `hasPermission()` method to check permission status without requesting.
* feat: Add AAC/ADTS streaming.
* fix: `AudioInterruptionMode.pauseResume` now ignores SDK `.shouldResume` flag.

## 1.1.5
* fix: Clamp to supported sample rates for Opus.

## 1.1.4
* fix: Wrong deprecation on allowBluetooth on XCode 26.0.

## 1.1.3
* fix: Recording should resume after pause when in background.

## 1.1.2
* fix: Audio interruption with incoming call.

## 1.1.1
* fix: Calling stop never ends when not recording.

## 1.1.0
* feat: Add AudioInterruptionMode to `RecordConfig`.
* feat: Add stream buffer size option.
* feat: Allow background recording.

## 1.0.0
* chore: Support Swift Package Manager.
* chore: Set SDK version to >= 12.0.
* fix: Properly dispose recorder on app termination.