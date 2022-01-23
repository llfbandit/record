## 3.0.3
* core: Moved from jcenter to mavenCentral (Android).

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
