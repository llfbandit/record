Audio recorder from microphone to a given file path.
No external dependencies, MediaRecorder is used for Android an AVAudioRecorder for iOS.

## Options
- bit rate (be careful with this one on iOs)
- sampling rate
- encoder

## Platforms

### Android
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<!-- Optional, you'll have to check this permission by yourself. -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```
min SDK: 16 (29 if you use OPUS)

### iOs
```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need to access to the microphone to record audio file</string>
```
min SDK: 8.0 (11 if you use OPUS)

## Supported encoders
```dart

enum AudioEncoder {
  /// Will output to MPEG_4 format container
  AAC,

  /// Will output to MPEG_4 format container
  AAC_LD,

  /// Will output to MPEG_4 format container
  AAC_HE,

  /// sampling rate should be set to 8kHz
  /// Will output to 3GP format container on Android
  AMR_NB,

  /// sampling rate should be set to 16kHz
  /// Will output to 3GP format container on Android
  AMR_WB,

  /// Will output to MPEG_4 format container
  /// /!\ SDK 29 on Android /!\
  /// /!\ SDK 11 on iOs /!\
  OPUS,
}
```

### Android
https://developer.android.com/reference/android/media/MediaRecorder.AudioEncoder
### iOs
https://developer.apple.com/documentation/coreaudiotypes/coreaudiotype_constants/1572096-audio_data_format_identifiers

## Usage
```dart
// Import package
import 'package:record/record.dart';

// Check and request permission
bool result = await Record.hasPermission();

// Start recording
await Record.start(
  path: 'aFullPath/myFile.m4a', // required
  encoder: AudioEncoder.AAC, // by default
  bitRate: 128000, // by default
  sampleRate: 44100, // by default
);

// Stop recording
await Record.stop();

// Get the state of the recorder
bool isRecording = await Record.isRecording();

// There's nothing to dispose, this done internally each time you call stop method.
// The plugin is aware of activity lifecycle.
// So exiting, your app or activity will stop the recording (but won't delete the 
// output file).
```

## Warnings
Be sure to check supported values from the given links above.

## Known issues
None.