## 5.0.4
* fix: Regression on creation sequence when disposing `AudioRecorder` without using it.

## 5.0.3
* fix: Regression on creation sequence when disposing `AudioRecorder` without using it.

## 5.0.2
* fix: Creation sequence which may lead to unexpected behaviours.

## 5.0.1
* fix: close state stream controller on dispose.

## 5.0.0
* Chore:
    * Massively reworked platform implementations.
    * Android now uses MediaCodec. Package is now written with kotlin (well...).
    * iOS, macOS code now shares almost the same codebase. Unified under record_darwin package.
    * Windows now uses MediaFoundation shipped with all 10 & 11 versions (no more fmedia executable, yeah! Even if do appreciate the work of stsaz).

* Features:
    * feat: Add multiple instance support.
    * feat: Add PCM streaming feature & AAC on Android only.
    * feat: Add auto gain control, noise suppressor and echo cancellation where available.
    * feat: Add amplitude on web (Thanks to [youssefali424](https://github.com/youssefali424)).
    * feat: Add best effort to adjust sample and bit rates to supported values (Android, iOS, macOS).
    * feat: Add `cancel()` method to stop and remove file if any.

* Fix:
    * iOS: Should pause/resume recording when interrupted by the system.
    * web: Add duration metadata to created blob (Thanks to [youssefali424](https://github.com/youssefali424)).

* Breaking changes:
    * BREAK: `Record` has been renamed to `AudioRecorder` to avoid confusion with dart v3.
    * BREAK: path is now required on all IO platforms. Set an empty String on web platform.
    There no more temp file generation.
    * BREAK: `start` and `startStream` method parameters are now wrapped in `RecordConfig` object.
    * BREAK: `samplingRate` has been renamed to `sampleRate`.
    * BREAK: vorbis support has been removed. Too few underlying support.

## 5.0.0-beta.3+1
* fix: Amplitude timer is not restarted for subsequent recordings.
* chore: Allow UUID v3 & V4.

## 5.0.0-beta.3
* fix: Adding events to amplitude stream after close

## 5.0.0-beta.2
* chore: remove `pcm8bit`. Virtually still available since we have pcm 16 bits.
* chore: throw exception when encoder is not supported.
* fix(web): Multiple issues on web platform.
* fix: Other minor fixes.
* feat(web): Add WAVE encoder support (16 bits).
* feat: add utility method `convertBytesToInt16` to convert Uint8List to signed int 16 bits.

## 5.0.0-beta.1
**Testers needed to reach release !**
***

* Chore:
    * Massively reworked platform implementations.
    * Android now uses MediaCodec. Package is now written with kotlin (well...).
    * iOS, macOS code now shares almost the same codebase. Unified under record_darwin package.
    * Windows now uses MediaFoundation shipped with all 10 & 11 versions (no more fmedia executable, yeah! Even if do appreciate the work of stsaz).

* Features:
    * feat: Add multiple instance support.
    * feat: Add PCM streaming feature & AAC on Android only (for now).
    * feat: Add auto gain control, noise suppressor and echo cancellation where available.
    * feat: Add amplitude on web (Thanks to [youssefali424](https://github.com/youssefali424)).
    * feat: Add best effort to adjust sample and bit rates to supported values (Android, iOS, macOS).
    * feat: Add `cancel()` method to stop and remove file if any.

* Fix:
    * iOS: Should pause/resume recording when interrupted by the system.
    * web: Add duration metadata to created blob (Thanks to [youssefali424](https://github.com/youssefali424)).

* Breaking changes:
    * BREAK: `Record` has been renamed to `AudioRecorder` to avoid confusion with dart v3.
    * BREAK: path is now required on all IO platforms. Set an empty String on web platform.
    There no more temp file generation.
    * BREAK: `start` and `startStream` method parameters are now wrapped in `RecordConfig` object.
    * BREAK: `samplingRate` has been renamed to `sampleRate`.
    * BREAK: vorbis support has been removed. Too few underlying support.

## 4.4.4
* chore: Update linter rules.
* chore: Update dependencies.
* chore: Update readme.md.

## 4.4.3
* fix: Deprecation warning on Android.
* fix: Android build issue.
* fix: Don't report Android exception when stop is called just after start.

## 4.4.2
* fix: Android build issue with linter.

## 4.4.1
* fix: Android build issue with linter.

## 4.4.0
* feat: `onStateChanged()` stream is now filled by platform implementations.
    * This allows more reliable updated record states.
* fix: `onAmplitudeChanged` could result in computation error.
* core: Updated flutter to min 2.8.1.
* core: Updated example to use above streams.

## 4.3.3
* fix: WAV header overwrites first 44 data bytes.

## 4.3.2
* fix: Android `hasPermission()` method does not throw exception anymore when permission has been denied.

## 4.3.1
* fix: iOS compilation.

## 4.3.0
* feat: Add input devices listing and selection (linux / windows / macOS / web).
* feat: Add number of channels.
* core: fmedia updated to 1.28 (linux / windows).
* feat: Add recorder state stream.
* feat: Add recorder amplitude stream.
* core: Update dependencies.
* fix: Add error details on record start (ios).
* fix: WAV recording header, resume-pause (Android).

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
