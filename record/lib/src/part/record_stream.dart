part of '../record.dart';

/// Methods for stream recording.
mixin _StreamMixin {
  StreamController<Uint8List>? _recordStreamCtrl;
  StreamSubscription? _recordStreamSubscription;

  Future<Stream<Uint8List>> _startRecordStream(Stream<Uint8List> stream) async {
    _recordStreamCtrl ??= StreamController.broadcast();

    _recordStreamSubscription = stream.listen(
      (data) {
        if (_recordStreamCtrl case final ctrl? when ctrl.hasListener) {
          ctrl.add(data);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_recordStreamCtrl case final ctrl? when ctrl.hasListener) {
          ctrl.addError(error, stackTrace);
        }
      },
      // The platform may end capture on its own: end the caller's stream too.
      onDone: () {
        final ctrl = _recordStreamCtrl;
        _recordStreamCtrl = null;
        _recordStreamSubscription = null;
        ctrl?.close();
      },
    );

    return _recordStreamCtrl!.stream;
  }

  /// Stops and closes the record stream.
  Future<void> _stopRecordStream() async {
    await _recordStreamSubscription?.cancel();
    _recordStreamSubscription = null;
    await _recordStreamCtrl?.close();
    _recordStreamCtrl = null;
  }
}
