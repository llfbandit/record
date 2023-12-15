## 1.0.4
* fix: Audio recording on Firefox.
* fix: Mic usage icon does not dismiss.

## 1.0.3
* fix: Regression on chrome based browsers when numChannels don't match size of inputs.

## 1.0.2
* feat: Add acceptable resampling (up and down) feature for browsers that don't support it natively.

## 1.0.1
* fix: Firefox, does not provide resampling feature (see README.md).

## 1.0.0
* chore: Initial stable release.

## 1.0.0-beta.2+4
* fix: num channels config adjustment.
* fix: improve resource disposing.

## 1.0.0-beta.2+3
* fix: sample rate / num channels config mismatching.
* fix: media stream not properly closed.
* feat: try to limit config according to capabilities (Chrome/Edge OK, Firefox 117 not implemented).

## 1.0.0-beta.2+2
* fix: PCM/WAV recording.
* feat: float 32 to int 16 conversion is now done in web audio thread.

## 1.0.0-beta.2+1
* fix: PCM float 32 to int 16 conversion.
* fix: Wrong call in WAV encorder to get char code.
* fix: Share init/reset code in delegates.

## 1.0.0-beta.2
* fix: PCM streaming.
* fix: Don't record if encoder is not supported.
* feat: Add WAVE encoder support (16bits).

## 1.0.0-beta.1+1
* fix: `stop` is completing with required String.
* fix: Sync stop with current stream.

## 1.0.0-beta.1
* chore: Change signature of `start` method.
* feat: Add multiple instance support.
* feat: Add amplitude.
* feat: Add `startStream` method.
* feat: Add `cancel` method.
* fix: Add duration metadata in created blob.

## 0.5.0
- feat: `onStateChanged()` implementation.

## 0.4.0
- feat: Add input devices listing.
- feat: Add number of channels.

## 0.3.1
- fix: Close media stream after recording.
- core: Flutter lints added.

## 0.3.0
- feat: Allow codec selection.

## 0.2.1
- Fix record_platform_interface version.

## 0.2.0
- Update dependencies.

## 0.1.0
- Initial release.
