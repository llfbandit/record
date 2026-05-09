import 'dart:async';
import 'dart:collection';

/// A class that represents a semaphore.
class Semaphore {
  final int maxCount = 1;

  int _counter = 0;
  final _waitQueue = Queue<Completer>();

  /// Acquires a permit from this semaphore, asynchronously blocking until one
  /// is available.
  Future acquire() {
    var completer = Completer();
    if (_counter + 1 <= maxCount) {
      _counter++;
      completer.complete();
    } else {
      _waitQueue.add(completer);
    }
    return completer.future;
  }

  /// Releases a permit, returning it to the semaphore.
  void release() {
    if (_counter == 0) {
      throw StateError("Unable to release semaphore.");
    }
    _counter--;
    if (_waitQueue.isNotEmpty) {
      _counter++;
      var completer = _waitQueue.removeFirst();
      completer.complete();
    }
  }
}
