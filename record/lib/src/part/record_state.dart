part of '../record.dart';

/// Methods for state management.
mixin _StateMixin {
  StreamController<RecordState>? _stateStreamCtrl;
  StreamSubscription? _stateStreamSubscription;

  /// Listen to recorder states [RecordState].
  ///
  /// Provides pause, resume and stop states.
  ///
  /// Also, you can retrieve async errors from it by adding [Function? onError] callback to the subscription.
  Stream<RecordState> _onStateChanged(
      RecordPlatform platform, String recorderId) {
    if (_stateStreamCtrl case final ctrl?) {
      return ctrl.stream;
    }

    _stateStreamCtrl = StreamController<RecordState>.broadcast();

    _stateStreamSubscription = platform.onStateChanged(recorderId).listen(
      (state) {
        if (_stateStreamCtrl case final ctrl? when ctrl.hasListener) {
          ctrl.add(state);
        }
      },
      onError: (error) {
        if (_stateStreamCtrl case final ctrl? when ctrl.hasListener) {
          ctrl.addError(error);
        }
      },
    );

    return _stateStreamCtrl!.stream;
  }

  /// Disposes state stream resources.
  Future<void> _disposeState() async {
    await _stateStreamSubscription?.cancel();
    await _stateStreamCtrl?.close();
    _stateStreamCtrl = null;
  }
}
