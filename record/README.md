Audio recorder from microphone to a given file path or stream.  

No external dependencies:

- On Android, AudioRecord and MediaCodec.
- On iOS and macOS, AVFoundation.
- On Windows, MediaFoundation.
- On web, well... your browser! (and its underlying platform).

External dependencies:
- On linux, encoding is provided by [fmedia](https://stsaz.github.io/fmedia/). It **must** be installed separately.

## Platform feature parity matrix
| Feature          | Android       | iOS             | web     | Windows    | macOS  | linux
|------------------|---------------|-----------------|---------|------------|-------|-----------
| pause/resume     | ✔️            |   ✔️           | ✔️     |      ✔️    | ✔️    |  ✔️
| amplitude(dBFS)  | ✔️            |   ✔️           |  ✔️     |    ✔️     |  ✔️   |
| permission check | ✔️            |   ✔️           |  ✔️    |            |  ✔️   |
| num of channels  | ✔️            |   ✔️           |  ✔️    |    ✔️      |  ✔️   |  ✔️
| device selection |              | (auto BT/mic)   |  ✔️    |    ✔️      |  ✔️   |  ✔️
| auto gain        | ✔️            |(always active?)| ✔️      |            |       |  
| echo cancel      | ✔️            |                 | ✔️      |            |       |  
| noise suppresion | ✔️            |                 | ✔️      |            |       |  

Bluetooth is not supported on Android at this time.

## File
| Encoder         | Android        | iOS     | web     | Windows | macOS   | linux
|-----------------|----------------|---------|---------|---------|---------|---------
| aacLc           | ✔️            |   ✔️    |  ?     |   ✔️    |  ✔️    |  ✔️ 
| aacEld          | ✔️            |   ✔️    |   ?     |         |  ✔️    | 
| aacHe           | ✔️            |         |   ?     |         |         |  ✔️ 
| amrNb           | ✔️            |         |  ?      |   ✔️    |         |  
| amrWb           | ✔️            |         |  ?      |          |        |  
| opus            | ✔️            |         |  ✔️      |         |         |  ✔️ 
| wav             |  ✔️           |   ✔️    |   ✔️     |    ✔️    |   ✔️  |   ✔️ 
| flac            |  ✔️           |    ✔️    |  ?      |  ✔️     |   ✔️  |   ✔️
| pcm16bits       | ✔️            |   ✔️    |  ✔️      |   ✔️    |  ✔️   |  

\* Question marks (?) in web column mean that the formats are supported by the plugin
but are not available in current (and tested) browsers (Chrome / Firefox).

## Stream
| Encoder         | Android    | iOS     | web     | Windows | macOS   | linux
|-----------------|------------|---------|---------|---------|---------|---------
| aacLc       *   | ✔️        |         |          |         |         |  
| aacEld      *   | ✔️        |         |          |         |         | 
| aacHe       *   | ✔️        |         |          |         |         |  
| pcm16bits       | ✔️        |  ✔️    |   ✔️    |  ✔️     | ✔️     |  

\* AAC is streamed with raw AAC with ADTS headers, so it's directly readable through a file!  

__All audio output is with 16bits depth.__

## Usage

```dart
import 'package:record/record.dart';

final record = AudioRecorder();

// Check and request permission if needed
if (await record.hasPermission()) {
  // Start recording to file
  await record.start(const RecordConfig(), path: 'aFullPath/myFile.m4a');
  // ... or to stream
  final stream = await record.startStream(const RecordConfig(AudioEncoder.pcm16bits));
}

// Stop recording...
final path = await record.stop();
// ... or cancel it (and implicitly remove file/blob).
await record.cancel();

record.dispose(); // As always, don't forget this one.
```

## Setup, permissions and others

### Android
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```
- min SDK: 21 (amrNb/amrWb: 26, Opus: 29)

* [Audio formats sample rate hints](https://developer.android.com/guide/topics/media/media-formats#audio-formats)

### iOS
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Some message to describe why you need this permission</string>
```
- min SDK: 11.0

### macOS
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Some message to describe why you need this permission</string>
```

- In capabilities, activate "Audio input" in debug AND release schemes.  
- or directly in *.entitlements files
```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

- min SDK: 10.15
