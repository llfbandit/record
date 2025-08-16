# Audio Effects Usage Example

The Windows audio recording plugin now supports the following audio enhancement effects:

## Available Effects
- **Noise Suppression**: Reduces background noise during recording
- **Echo Cancellation**: Eliminates echo and feedback 
- **Automatic Gain Control (AGC)**: Automatically adjusts microphone levels

## Usage from Flutter/Dart

```dart
import 'package:record/record.dart';

// Enable all audio effects
const config = RecordConfig(
  encoder: AudioEncoder.aacLc,
  numChannels: 1,
  sampleRate: 48000,
  // Enable audio effects
  noiseSuppress: true,     // Enable noise suppression
  echoCancel: true,        // Enable echo cancellation  
  autoGain: true,          // Enable automatic gain control
);

// Start recording with effects
await recorder.start(config, path: 'output.m4a');
```

## How It Works

The effects are implemented using Windows Audio Processing APIs:

1. **AudioCategory_Communications**: Sets the audio stream to Communications category, which automatically enables Windows' built-in voice processing effects when supported by the audio driver.

2. **IAudioClient2**: Uses Windows 8+ audio client interface to configure advanced audio processing options.

3. **AUDCLNT_STREAMOPTIONS_RAW**: Enables raw processing mode for better voice enhancement.

## Compatibility

- **Windows Version**: Windows 8+ (IAudioClient2 required)
- **Driver Support**: Effects depend on audio driver capabilities
- **Fallback**: If effects are not supported, recording continues without effects
- **Auto-Detection**: Windows automatically applies available effects based on hardware/driver support

## Technical Details

Effects are enabled during WASAPI audio client initialization by:
- Setting `AudioCategory_Communications` stream category
- Using `AUDCLNT_STREAMOPTIONS_RAW` processing mode
- Configuring `AudioClientProperties` for voice enhancement

The implementation is hardware-agnostic and works with any Windows-compatible audio device that supports these effects through its driver.

## Testing

You can verify effects are working by:
1. Recording in a noisy environment (noise suppression)
2. Recording with speakers playing (echo cancellation)  
3. Recording at different distances from microphone (auto gain)

Effects will only be applied if:
- The audio driver supports them
- Windows Audio Engine can apply them
- The recording device is compatible

No additional libraries or dependencies are required - all effects use built-in Windows APIs.
