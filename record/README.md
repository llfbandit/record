Audio recorder from microphone to a given file path or stream.  

No external dependencies:

- On Android, AudioRecord and MediaCodec or MediaRecorder.
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
| device selection | ✔️ 1 / 2      | (auto BT/mic)   |  ✔️    |    ✔️      |  ✔️   |  ✔️
| auto gain        | ✔️ 2          |(always active?)| ✔️      |            |       |  
| echo cancel      | ✔️ 2          |                 | ✔️      |            |       |  
| noise suppresion | ✔️ 2          |                 | ✔️      |            |       |  

## File
| Encoder         | Android        | iOS     | web     | Windows | macOS   | linux
|-----------------|----------------|---------|---------|---------|---------|---------
| aacLc           | ✔️            |   ✔️    |  ?      |   ✔️    |  ✔️    |  ✔️ 
| aacEld          | ✔️            |   ✔️    |   ?     |         |  ✔️    | 
| aacHe           | ✔️            |         |   ?     |         |         |  ✔️ 
| amrNb           | ✔️            |         |  ?      |   ✔️    |         |  
| amrWb           | ✔️            |         |  ?      |          |        |  
| opus            | ✔️            |         |  ?    |         |         |  ✔️ 
| wav             | ✔️ 2          |   ✔️    |   ✔️   |    ✔️    |   ✔️  |   ✔️ 
| flac            | ✔️ 2          |    ✔️    |  ?     |  ✔️     |   ✔️   |   ✔️
| pcm16bits       | ✔️ 2          |   ✔️    |  ✔️    |   ✔️    |  ✔️    |  

?: from my testings:
| Encoder         | Firefox    | Chrome based   | Safari
|-----------------|------------|----------------|---------
| aacLc           |            |                |  ✔️*
| opus            | ✔️*        |   ✔️*           | 
| wav             | ✔️        |   ✔️           |   ✔️
| pcm16bits       | ✔️        |   ✔️           |  ✔️

\* Sample rate output is determined by your settings in OS. Bit depth is likely 32 bits.

wav and pcm16bits are provided by the package directly.

## Stream
| Encoder         | Android    | iOS     | web     | Windows | macOS   | linux
|-----------------|------------|---------|---------|---------|---------|---------
| aacLc       *   | ✔️ 2      |         |          |         |         |  
| aacEld      *   | ✔️ 2      |         |          |         |         | 
| aacHe       *   | ✔️ 2      |         |          |         |         |  
| pcm16bits       | ✔️ 2      |  ✔️    |   ✔️    |  ✔️     | ✔️     |  

\* AAC is streamed with raw AAC with ADTS headers, so it's directly readable through a file!  
1. Bluetooth telephony device link (SCO) is automatically done but there's no phone call management.
2. Unsupported on legacy Android recorder.

## Usage

```dart
import 'package:record/record.dart';

final record = AudioRecorder();

// Check and request permission if needed
if (await record.hasPermission()) {
  // Start recording to file
  await record.start(const RecordConfig(), path: 'aFullPath/myFile.m4a');
  // ... or to stream
  final stream = await record.startStream(const RecordConfig(encoder: AudioEncoder.pcm16bits));
}

// Stop recording...
final path = await record.stop();
// ... or cancel it (and implicitly remove file/blob).
await record.cancel();

record.dispose(); // As always, don't forget this one.
```

## Setup, permissions and others

### Android
Follow [Gradle setup](https://github.com/llfbandit/record/blob/master/record_android/README.md) if needed.

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<!-- Optional: Add this permission if you want to use bluetooth telephony device like headset/earbuds -->
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<!-- Optional: Add this permission if you want to save your recordings in public folders -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```
- min SDK: 23 (amrNb/amrWb: 26, Opus: 29)

* [Audio formats sample rate hints](https://developer.android.com/guide/topics/media/media-formats#audio-formats)

Effects (auto gain, echo cancel and noise suppressor) may be unvailable for a specific device.  
Please, stop opening issues if it doesn't work for one device but for the others.

There is no gain settings to play with, so you cannot control the volume of the audio being recorded.  
The low volume of the audio is related to the hardware and varies from device to device.

Applying effects will lower the output volume. Choosing source other than default or mic will likely lower the output volume also.

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

### Web

Web platform uses package web >=0.5.1 which is shipped with Flutter >=3.22.

This platform is still available with previous Flutter versions but continuous work is done from this version only.
