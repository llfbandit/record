# record iOS & macOS

iOS & macOS implementations for record package called by record_platform_interface.

## Tests

Unit tests live in `darwin/Tests`. The example app builds them in its `RunnerTests` target, so
they run against the real plugin module on both platforms:

```sh
cd ../record/example

xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -destination 'platform=macOS'

xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17'
```
