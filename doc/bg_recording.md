# Background recording

## Android

Add the following the manifest in `android/app/src/main/AndroidManifest.xml`:

```xml
<!-- Record permissions for background recording -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<application>
    <!-- Record background recording service declaration -->
    <service
        android:name="com.llfbandit.record.service.AudioRecordingService"
        android:foregroundServiceType="microphone"
        android:exported="false" />
</application>
```

When starting recording, you need to enable the service explicitly by setting the following in the given config:
```dart
RecordConfig(
  ...,
  androidConfig: AndroidRecordConfig(service: AndroidService(title: 'Title', content: 'Content...'))
);
```

A notification is added (with low importance) to conform to Android requirements if service is started.

## iOS

Add the following in `ios/Runner/info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
  <string>fetch</string>
</array>
```

If you use `AudioInterruptionMode.pauseResume`, you must include `IosAudioCategoryOptions.mixWithOthers`.

[stackoverflow reference](https://stackoverflow.com/questions/29036294/avaudiorecorder-not-recording-in-background-after-audio-session-interruption-end/35544795#35544795)