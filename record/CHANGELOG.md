## 4.1.1
* core: README.md updates.

## 4.1.0
* feat: Add linux platform. EXPERIMENTAL.

## 4.0.2
* core: Replace SFML by fmedia.
* feat: More encoders and features on Windows.
* fix: Windows build by removing SFML.
* core: README.md updates.

## 4.0.1
* core: OPUS and vorbis formats are now in OGG containers (instead of MP4).
* core: Relax dependencies version constraints.
* core: README.md updates.

## 4.0.0
This contains very small breaking changes. See below.
* core: BREAK: `AudioEncoder` values are now in lowerCamelCase.
* core: BREAK? or fix: `start#samplingRate` is now an integer.
* core: BREAK: `AudioEncoder.aac` is now `AudioEncoder.aacLc`.
* core: Android minimum API level is now 19.
* core: dart minimum version is now 2.15.
* core: Update dependencies.
* core: README.md updates.
* core: License changed from Apache 2.0 to BSD-3-Clause.

* feat: Add Windows platform support.
* feat: Add macOS platform support.
* feat: Codec is now applied in web platform (if available).
* feat: Add vorbisOgg, WAV, FLAC, PCM 8 bits, PCM 16 bits.
* feat: Add `isEncoderSupported` to check if the encoder is available on the platform.

## 3.0.4
* fix: iOS - hasPermission double check was needed when permission was undeterminated.

## 3.0.3
* core: Moved from jcenter to mavenCentral (Android).
* feat: Use average instead of peak power (iOS).

## 3.0.2
* fix: web `pubspec.yaml` file.

## 3.0.1
* fix: Android request code is now frozen.
* core: Update dependencies.

## 3.0.0
* feat: Add web support.
* feat: Add `getAmplitude()` to get current and max dBFS.
* core: static methods are no more! (but api is pretty much the same)
* core: path param is now optional in `start` method to align behaviour with web platform.  
If null is given, a temp file is generated for you.
* core: `stop` method now returns the output path.

## 2.1.1
* fix: Android warning "mediarecorder went away with unhandled events".

## 2.1.0+1
* Relaxing dart/flutter constraints for pub.dev analysis.

## 2.1.0
* Add pause/resume/isPaused features.
* Updated example to include pause.

## 2.0.0
* Add null safety support (based on v1.0.3).
* Updated example. Moved from 'audioplayers' to 'just_audio'.

## 1.0.3
* Allow recording from bluetooth device on iOS.

## 1.0.2
* Fix (for good) potential exception when closing beofre recorder is actually started (Android).

## 1.0.1
* Fix potential exception when closing beofre recorder is actually started (Android).
* Fix potential NPE on permission result (Android).
* Updade dependencies.

## 1.0.0

* Flutter 1.12.0 is now minimum version (Flutter plugin API v2).
* Finalize Record API.
* Request permission on Android too.
* Automatically stop recording when leaving activity / app.
* Add all codecs with cross platform compatibility.

## 0.2.1

* Fix broken build on Android.

## 0.2.0

* Fix broken build on Android.

## 0.1.0

* Initial release.
* Implementations for Android and iOs.
* Example.
