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
    );

    return _recordStreamCtrl!.stream;
  }

  /// Stops and closes the record stream.
  Future<void> _stopRecordStream() async {
    await _recordStreamSubscription?.cancel();
    await _recordStreamCtrl?.close();
    _recordStreamCtrl = null;
  }
}
