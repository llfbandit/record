# record Android

Android specific implementation for record package called by record_platform_interface.

## Setup

### Permissions:
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<!-- Optional: Add this permission if you want to use bluetooth telephony device like headset/earbuds -->
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<!-- Optional: Add this permission if you want to save your recordings in public folders -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```


* [Audio formats sample rate hints](https://developer.android.com/guide/topics/media/media-formats#audio-formats)

Effects (auto gain, echo cancel and noise suppressor) may be unvailable for a specific device.  
Please, stop opening issues if it doesn't work for one device but for the others.

There is no gain settings to play with, so you cannot control the volume of the audio being recorded.  
The low volume of the audio is related to the hardware and varies from device to device.

Applying effects will lower the output volume. Choosing source other than default or mic will likely lower the output volume also.