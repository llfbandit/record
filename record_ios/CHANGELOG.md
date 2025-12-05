## Upcoming
* feat: Add `request` parameter to `hasPermission()` method to check permission status without requesting.

## 1.1.5
* fix: Clamp to supported sample rates for Opus.

## 1.1.4
* fix: Wrong deprecation on allowBluetooth on XCode 26.0.

## 1.1.3
* fix: Recording should resume after pause when in background.

## 1.1.2
* fix: Audio interruption with incoming call.

## 1.1.1
* fix: Calling stop never ends when not recording.

## 1.1.0
* feat: Add AudioInterruptionMode to `RecordConfig`.
* feat: Add stream buffer size option.
* feat: Allow background recording.

## 1.0.0
* chore: Support Swift Package Manager.
* chore: Set SDK version to >= 12.0.
* fix: Properly dispose recorder on app termination.