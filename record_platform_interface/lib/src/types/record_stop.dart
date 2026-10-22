/// Why a take ended.
enum RecordStopReason {
  /// The app ended it: `stop()`, `cancel()`, `dispose()`, or a new `start()`.
  stop,

  /// The input went away, with `AudioRouteChangeMode.stop`.
  routeChange,

  /// An interruption (e.g. a phone call) ended it.
  interruption,

  /// Capture or encoding failed.
  error,
}

/// The end of a take.
class RecordStop {
  const RecordStop({required this.reason, this.path, this.error});

  /// Why the take ended.
  final RecordStopReason reason;

  /// The file, as `stop()` returns it. Null after `cancel()`, and for a stream.
  final String? path;

  /// What failed, for [RecordStopReason.error].
  final String? error;

  factory RecordStop.fromMap(Map map) {
    return RecordStop(
      reason: RecordStopReason.values.byName(map['reason'] as String),
      path: map['path'] as String?,
      error: map['error'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RecordStop &&
      other.reason == reason &&
      other.path == path &&
      other.error == error;

  @override
  int get hashCode => Object.hash(reason, path, error);

  @override
  String toString() =>
      'RecordStop(reason: ${reason.name}, path: $path, error: $error)';
}
