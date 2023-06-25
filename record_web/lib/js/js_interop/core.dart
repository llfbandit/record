@JS('self')
@staticInterop
library dom;

import 'dart:js_util' as jsu;

import 'package:js/js.dart';

typedef EventHandlerNonNull<T extends Event> = Function(T event);

@JS()
external dynamic undefined;

@anonymous
@JS()
@staticInterop
class DoubleRange {
  external factory DoubleRange({double? max, double? min});
}

extension PropsDoubleRange on DoubleRange {
  double get max => jsu.getProperty(this, 'max');
  set max(double newValue) {
    jsu.setProperty(this, 'max', newValue);
  }

  double get min => jsu.getProperty(this, 'min');
  set min(double newValue) {
    jsu.setProperty(this, 'min', newValue);
  }
}

@anonymous
@JS()
@staticInterop
class ULongRange {
  external factory ULongRange({int? max, int? min});
}

extension PropsULongRange on ULongRange {
  int get max => jsu.getProperty(this, 'max');
  set max(int newValue) {
    jsu.setProperty(this, 'max', newValue);
  }

  int get min => jsu.getProperty(this, 'min');
  set min(int newValue) {
    jsu.setProperty(this, 'min', newValue);
  }
}

@JS()
@staticInterop
class Event {
  external factory Event._(String type, [EventInit? eventInitDict]);

  factory Event(String type, [EventInit? eventInitDict]) =>
      Event._(type, eventInitDict ?? undefined);
  @JS('NONE')
  external static int get none;

  @JS('CAPTURING_PHASE')
  external static int get capturingPhase;

  @JS('AT_TARGET')
  external static int get atTarget;

  @JS('BUBBLING_PHASE')
  external static int get bubblingPhase;
}

@anonymous
@JS()
@staticInterop
class EventInit {
  external factory EventInit._(
      {bool? bubbles, bool? cancelable, bool? composed});

  factory EventInit({bool? bubbles, bool? cancelable, bool? composed}) =>
      EventInit._(
          bubbles: bubbles ?? false,
          cancelable: cancelable ?? false,
          composed: composed ?? false);
}

@JS('Map')
@staticInterop
class JsMap<K extends Object, V> {
  external factory JsMap([Iterable<Iterable> initial]);
}

extension DartMap<K extends Object, V> on JsMap<K, V> {
  V? operator [](K key) => jsu.callMethod(this, 'get', [key]);

  operator []=(K key, V? value) {
    jsu.callMethod(this, 'set', [key, value]);
  }

  bool remove(K key) => jsu.callMethod(this, 'delete', [key]);

  void removeAll(Iterable<K> keys) {
    for (final key in keys) {
      remove(key);
    }
  }

  JsIterable<V> get keys => jsu.callMethod(this, 'keys', const []);

  JsIterable<V> get values => jsu.callMethod(this, 'values', const []);

  bool containsKey(K key) => jsu.callMethod(this, 'has', [key]);

  void clear() {
    jsu.callMethod(this, 'clear', const []);
  }

  void forEach(void Function(K, V?, JsMap<K, V>) fn) {
    jsu.callMethod(this, 'forEach', [allowInterop(fn)]);
  }
}

@anonymous
@JS('Iterator')
@staticInterop
class JsIterator<T> {
  external factory JsIterator();
}

@JS('Symbol.iterator')
external Symbol get _iterator;

extension PropsIterator<T> on JsIterator<T> {
  Iterable<T> toIterable() sync* {
    final iterator = jsu.getProperty(this, _iterator);
    final callable = (jsu.callMethod(iterator, 'bind', [this]) as Function())();

    while (true) {
      final result = _next(callable);
      if (result.done) {
        break;
      }
      yield result.value;
    }
  }

  IteratorResult<T> _next(dynamic iteratorInstance) {
    return jsu.callMethod(iteratorInstance, 'next', []);
  }

  IteratorResult<T> next() => jsu.callMethod(this, 'next', []);
}

@anonymous
@JS()
@staticInterop
class IteratorResult<T> {
  external factory IteratorResult();
}

extension PropsIteratorResult<T> on IteratorResult<T> {
  bool get done => jsu.getProperty(this, 'done');
  T get value => jsu.getProperty(this, 'value');
}

@JS()
@staticInterop
class JsIterable<E> implements JsIterator<E> {}

extension PropsIterable<E> on JsIterable<E> {
  List<E> toList() => [...toIterable()];
}

@JS()
@staticInterop
class BlobEvent implements Event {
  external factory BlobEvent(String type, BlobEventInit eventInitDict);
}

extension PropsBlobEvent on BlobEvent {
  Blob get data => jsu.getProperty(this, 'data');
  double get timecode => jsu.getProperty(this, 'timecode');
}

@anonymous
@JS()
@staticInterop
class BlobEventInit {
  external factory BlobEventInit({required Blob data, double? timecode});
}

extension PropsBlobEventInit on BlobEventInit {
  Blob get data => jsu.getProperty(this, 'data');
  set data(Blob newValue) {
    jsu.setProperty(this, 'data', newValue);
  }

  double get timecode => jsu.getProperty(this, 'timecode');
  set timecode(double newValue) {
    jsu.setProperty(this, 'timecode', newValue);
  }
}

@JS()
@staticInterop
class Blob {
  external factory Blob._(
      [Iterable<dynamic>? blobParts, BlobPropertyBag? options]);

  factory Blob([Iterable<dynamic>? blobParts, BlobPropertyBag? options]) =>
      Blob._(blobParts ?? undefined, options ?? undefined);
}

extension PropsBlob on Blob {
  int get size => jsu.getProperty(this, 'size');
  String get type => jsu.getProperty(this, 'type');
  Blob slice([int? start, int? end, String? contentType]) =>
      jsu.callMethod(this, 'slice', [start, end, contentType]);
}

enum EndingType {
  transparent('transparent'),
  native('native');

  final String value;
  static EndingType fromValue(String value) =>
      values.firstWhere((e) => e.value == value);
  static Iterable<EndingType> fromValues(Iterable<String> values) =>
      values.map(fromValue);
  const EndingType(this.value);
}

@anonymous
@JS()
@staticInterop
class BlobPropertyBag {
  external factory BlobPropertyBag._({String? type, String? endings});

  factory BlobPropertyBag({String? type, EndingType? endings}) =>
      BlobPropertyBag._(
          type: type ?? '',
          endings: endings?.value ?? EndingType.transparent.value);
}

extension PropsBlobPropertyBag on BlobPropertyBag {
  String get type => jsu.getProperty(this, 'type');
  set type(String newValue) {
    jsu.setProperty(this, 'type', newValue);
  }

  EndingType get endings =>
      EndingType.fromValue(jsu.getProperty(this, 'endings'));
  set endings(EndingType newValue) {
    jsu.setProperty(this, 'endings', newValue.value);
  }
}

@JS('URL')
@staticInterop
class Url {
  external factory Url._(String url, [String? base]);

  factory Url(String url, [String? base]) => Url._(url, base ?? undefined);
  external static String createObjectURL(dynamic obj);
  external static void revokeObjectURL(String url);
}
