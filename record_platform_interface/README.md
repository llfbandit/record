# record_platform_interface

A common platform interface for the [`record`][1] plugin.

This interface allows platform-specific implementations of the `record`
plugin, as well as the plugin itself, to ensure they are supporting the
same interface.

# Usage

To implement a new platform-specific implementation of `record`, extend
[`RecordPlatform`][2] with an implementation that performs the
platform-specific behavior, and when you register your plugin, set the default
`RecordPlatform` by calling
`RecordPlatform.instance = MyRecordPlatform()`.

# Note on breaking changes

Strongly prefer non-breaking changes (such as adding a method to the interface)
over breaking changes for this package.

See https://flutter.dev/go/platform-interface-breaking-changes for a discussion
on why a less-clean interface is preferable to a breaking change.

[1]: ../record
[2]: lib/record_platform_interface.dart