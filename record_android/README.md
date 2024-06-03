# record Android

Android specific implementation for record package called by record_platform_interface.

## Setup
### Plugin targets API level 34:

You must set Android Gradle Plugin to at least version 8.1.1 for compatibility.

In android/settings.gradle, apply:
```groovy
plugins {  
    id "com.android.application" version "8.3.1" apply false
    ...
}
```

### Plugin uses Java 17:

You must set Gradle to at least version 7.3.0 for compatibility.

Since we raised Android Gradle Plugin, minimum is version 8.4.

In android/gradle/wrapper/gradle-wrapper.properties, apply:
```
distributionUrl=https\://services.gradle.org/distributions/gradle-8.7-bin.zip
```

or use `android/gradle/gradlew wrapper --gradle-version=8.7`

For more info on how to update Gradle:
https://developer.android.com/build/releases/gradle-plugin
