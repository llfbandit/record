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