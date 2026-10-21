# record iOS & macOS

iOS & macOS implementations for record package called by record_platform_interface.

## Design

Sources are in `darwin/record_darwin/Sources/record_darwin`. Only `channel/` knows Flutter.
`core/` runs the takes. `ios/` and `macos/` give what changes between the two platforms.

```mermaid
flowchart TD
  Dart(["Dart: record_platform_interface"])

  subgraph channel["channel/ (Flutter)"]
    Plugin[RecordDarwinPlugin] --> Channel[RecorderChannel]
    Sink[ChannelSink]
  end

  subgraph core["core/"]
    Controller[RecorderController]
    Policy["TakePolicy, FormatPolicy"]
    Capture[AudioEngineCapture]
  end

  subgraph platform["RecorderPlatform"]
    Ios["IosPlatform<br/>IosAudioEnvironment, IosDeviceRegistry, IosInputRoute"]
    Mac["MacosPlatform<br/>MacosAudioEnvironment, MacosDeviceRegistry, MacosInputRoute"]
  end

  Dart -- method calls --> Plugin
  Channel -- one per recorder --> Controller
  Controller -- decides with --> Policy
  Controller -- one per take --> Capture
  Controller -- devices, interruptions --> platform
  Capture -- opens inputs with --> platform
  Controller -- states, stops, chunks --> Sink
  Sink -- events --> Dart
```

One take: the input feeds one output until the take ends. When the input moves, a new input feeds the same output.

```mermaid
flowchart LR
  Device((Input device)) --> Input

  subgraph Input["CaptureInput"]
    EngineInput["EngineInput (iOS)<br/>AVAudioEngine"]
    HalInput["HalInput (macOS)<br/>HAL or voice processing unit"]
  end

  Input --> Capture[AudioEngineCapture]
  Tracker["InputTracker<br/>which input, still there?"] -.- Capture
  Capture --> Output

  subgraph Output["CaptureOutput"]
    File["AudioFileOutput<br/>RawFileOutput (pcm16bits)"]
    Stream[StreamOutput]
  end

  File --> Disk[(File)]
  Stream --> Chunks([Chunks to Dart])
```

## Tests

Unit tests live in `darwin/Tests`. The example app builds them in its `RunnerTests` target, so
they run against the real plugin module on both platforms:

```sh
cd ../record/example

xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -destination 'platform=macOS'

xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17'
```
