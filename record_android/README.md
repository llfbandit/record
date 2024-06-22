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

### Plugin uses Java 17:

You must set Gradle to at least version 7.3 for compatibility. Android Gradle Plugin 7.4.0 requires >=7.5.

Here's the setup for v7 latest version:

In android/gradle/wrapper/gradle-wrapper.properties, apply:
```
distributionUrl=https\://services.gradle.org/distributions/gradle-7.6.4-bin.zip
```

or use `android/gradle/gradlew wrapper --gradle-version=7.6.4`

For more info on how to update Gradle:
https://developer.android.com/build/releases/gradle-plugin
