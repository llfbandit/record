Record audio with a given file path.
MediaRecorder for Android an AVAudioRecorder for iOS.

## Options
- bit rate (Android only, not working on iOs - quality is set to high for now)
- sampling rate
- encoder (Android only)
- output format

## Platforms
### Android
Permissions
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```
min SDK: 16

If your path is on external storage, you'll have to check the permission by yourself.

### iOs
```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need to access to the microphone to record</string>
```
min SDK: 8.0

## Supported formats & encoders
```dart
enum AudioOutputFormat {
  AAC,
  AMR_NB,
  AMR_WB,
  MPEG_4,
}

enum AudioEncoder {
  AAC,
  AMR_NB,
  AMR_WB,
}
```

### Android
https://developer.android.com/guide/topics/media/media-formats
### iOs
https://developer.apple.com/documentation/coreaudiotypes/coreaudiotype_constants/1572096-audio_data_format_identifiers

## Usage
```dart
// Import package
import 'package:record/record.dart';

// Start recording
await AudioRecorder.start(
    path: 'aFullPath', // required
    outputFormat: AudioOutputFormat.MPEG_4, // by default
    encoder: AudioEncoder.AAC, // by default (does nothing on iOs)
    bitRate: 128000, // by default
    sampleRate: 44100, // by default
    );

// Stop recording
await AudioRecorder.stop();

// Get the state of the recorder
bool isRecording = await Record.isRecording();

// There's nothing to dispose, this done internally.
```

## Warnings
Not all formats and/or rates are available for each platform.  
Be sure to check supported values from the given links above.