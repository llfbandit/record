part of '../record.dart';

typedef OnStateChanged = void Function(RecordState);

/// Methods for state management.
mixin _StateMixin {
  StreamController<RecordState>? _stateStreamCtrl;
  StreamSubscription? _stateStreamSubscription;
  StreamController<RecordStop>? _stopStreamCtrl;
  StreamSubscription? _stopStreamSubscription;

  /// Listen to recorder states [RecordState].
  ///
  /// Provides pause, resume and stop states.
  ///
  /// A take that fails ends with [RecordState.stop]: [onStopped] tells why.
  Stream<RecordState> _onStateChanged(
    RecordPlatform platform,
    String recorderId,
    OnStateChanged onStateChanged,
    Semaphore semaphore,
  ) {
    _stateStreamCtrl = StreamController<RecordState>.broadcast();
    _stopStreamCtrl = StreamController<RecordStop>.broadcast();

    semaphore.acquire().whenComplete(() {
      try {
        _stateStreamSubscription = platform
            .onStateChanged(recorderId)
            .listen(
              (state) {
                if (_stateStreamCtrl case final ctrl? when ctrl.hasListener) {
                  ctrl.add(state);
                }

                onStateChanged(state);
              },
              onError: (error) {
                if (_stateStreamCtrl case final ctrl? when ctrl.hasListener) {
                  ctrl.addError(error);
                }
              },
            );

        // Listened after the states, so a stop comes after RecordState.stop.
        _stopStreamSubscription = platform
            .onStopped(recorderId)
            .listen(
              (stop) {
                if (_stopStreamCtrl case final ctrl? when ctrl.hasListener) {
                  ctrl.add(stop);
                }
              },
              // The state stream reports errors.
              onError: (_) {},
            );
      } finally {
        semaphore.release();
      }
    });

    return _stateStreamCtrl!.stream;
  }

  /// Disposes state stream resources.
  Future<void> _disposeState() async {
    await _stateStreamSubscription?.cancel();
    _stateStreamSubscription = null;
    await _stopStreamSubscription?.cancel();
    _stopStreamSubscription = null;
    await _stateStreamCtrl?.close();
    _stateStreamCtrl = null;
    await _stopStreamCtrl?.close();
    _stopStreamCtrl = null;
  }
}
