# record Android

Android specific implementation for record package called by record_platform_interface.

## Setup
### Plugin targets API level 34:

You can either choose to stay with v7 version or upgrade to v8.

Here's the setup for v7 latest version:

In android/settings.gradle, apply:
```groovy
plugins {
    id "com.android.application" version "7.4.2" apply false
    ...
}
```
