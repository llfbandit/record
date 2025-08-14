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

A notification is added to conform to Android requirements.
```

## iOS

Add the following in `ios/Runner/info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```
