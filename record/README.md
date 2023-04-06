Audio recorder from microphone to a given file path.  

No external dependencies:

- On Android, AudioRecord is used.  
- On iOS, AVAudioRecorder is used.  
- On macOS, AVCaptureSession is used.  
- On web, well... your browser!

External dependencies:
- On Windows and linux, encoding is provided by [fmedia](https://stsaz.github.io/fmedia/).  
- On linux, fmedia must be installed separately.

## Options
- bit rate (where applicable)
- sampling rate
- encoder
- Number of channels
- Input device selection

## Platforms

### Android
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<!-- Optional, you'll have to check this permission by yourself. -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```
- min SDK: 21 (maybe higher => encoder dependent)

### iOS
```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need to access to the microphone to record audio file</string>
```
- min SDK: 11.0

### macOS
```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need to access to the microphone to record audio file</string>
```

- In capabilities, activate "Audio input" in debug AND release schemes

- min SDK: 10.15

## Platform feature parity matrix
| Feature          | Android        | iOS             | web     | Windows    | macOS  | linux
|------------------|----------------|-----------------|---------|------------|-------|-----------
| pause/resume     | ✔️             |   ✔️           | ✔️     |      ✔️    | ✔️    |  ✔️
| amplitude(dBFS)  | ✔️             |   ✔️           |         |            |  ✔️   |
| permission check | ✔️             |   ✔️           |  ✔️    |            |  ✔️   |
| num of channels  | ✔️             |   ✔️           |  ✔️    |    ✔️      |  ✔️   |  ✔️
| device selection | (auto BT/mic)  | (auto BT/mic)   |  ✔️    |    ✔️      |  ✔️   |  ✔️
| auto gain        | ✔️             |                 |         |            |       |  
| noise suppresion | ✔️             |                 |         |            |       |  

## File
| Encoder         | Android        | iOS     | web     | Windows | macOS   | linux
|-----------------|----------------|---------|---------|---------|---------|---------
| aacLc           | ✔️            |   ✔️    |  ?      |   ✔️    |  ✔️    |  ✔️ 
| aacEld          | ✔️            |   ✔️    |  ?      |         |  ✔️    | 
| aacHe           | ✔️            |   ✔️    |  ?      |   ✔️    |  ✔️    |  ✔️ 
| amrNb           | ✔️            |   ✔️    |  ?      |         |  ✔️    |  
| amrWb           | ✔️            |   ✔️    |  ?      |          |  ✔️   |  
| opus            | ✔️            |   ✔️    |  ?      |   ✔️    |  ✔️    |  ✔️ 
| vorbisOgg       | ?(optional)   |          |  ?      |  ✔️     |        |   ✔️  
| wav             |  ✔️           |         |  ?      |   ✔️     |        |   ✔️ 
| flac            |  ✔️           |    ✔️    |  ?      |  ✔️     |   ✔️  |   ✔️
| pcm8bit         | ✔️            |   ✔️    |  ?      |          |  ✔️   |  
| pcm16bit        | ✔️            |   ✔️    |  ?      |          |  ✔️   |  

## Stream
| Encoder         | Android        | iOS     | web     | Windows | macOS   | linux
|-----------------|----------------|---------|---------|---------|---------|---------
| aacLc           | ✔️*            |       |  **      |       |      |  
| aacEld          | ✔️*            |       |  **      |       |      | 
| aacHe           | ✔️*            |       |  **      |       |      |  
| pcm8bit         | ✔️            |       |   **     |       |     |  
| pcm16bit        | ✔️            |       |   **     |       |     |  

\* AAC is streamed with raw AAC with ADTS headers, so it can be saved as file.  
** web platform may allow more encoders.  


For every encoder, you should be really careful with given sampling rates.

If a given encoder is not supported when starting recording on platform, the fallbacks are:  

| Platform    | encoder                                                      
|-------------|--------------------------------------------------------------
| Android     | AAC LC                                                       
| iOS         | AAC LC                                                       
| web         | OPUS OGG (not guaranteed => choice is made by the browser)   
| Windows     | AAC LC                                                       
| macOS       | AAC LC                                                       
| linux       | AAC LC                                                       

## Encoding API levels documentation
### Android
* [MediaRecorder encoding constants](https://developer.android.com/reference/android/media/MediaRecorder.AudioEncoder)
* [Audio formats sample rate hints](https://developer.android.com/guide/topics/media/media-formats#audio-formats)

### iOS
* [AVAudioRecorder encoding constants](https://developer.apple.com/documentation/coreaudiotypes/coreaudiotype_constants/1572096-audio_data_format_identifiers)

## Usage
```dart
// Import package
import 'package:record/record.dart';

final record = Record();

// Check and request permission
if (await record.hasPermission()) {
  // Start recording to file
  await record.start(const RecordConfig(), path: 'aFullPath/myFile.m4a');
  // Start recording to stream
  final stream = await record.startStream(const RecordConfig());
}

// Get the state of the recorder
bool isRecording = await record.isRecording();

// Stop recording
await record.stop();
```

## Warnings
Be sure to check supported values from the given links above.

## Roadmap
- Allow to choose the capture device.
- Format vs. container accuracy.
- Bug fixes.