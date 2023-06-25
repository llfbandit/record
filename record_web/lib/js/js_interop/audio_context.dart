@JS('self')
@staticInterop
library webaudio;

import 'dart:js_util' as jsu;
import 'dart:typed_data';

import 'package:js/js.dart';

import 'core.dart';

enum AudioContextState {
  suspended('suspended'),
  running('running'),
  closed('closed');

  final String value;
  static AudioContextState fromValue(String value) =>
      values.firstWhere((e) => e.value == value);
  static Iterable<AudioContextState> fromValues(Iterable<String> values) =>
      values.map(fromValue);
  const AudioContextState(this.value);
}

///  The interface of the Web Audio API acts as a base definition for
/// online and offline audio-processing graphs, as represented by
/// [AudioContext] and [OfflineAudioContext] respectively. You
/// wouldn't use directly — you'd use its features via one of these
/// two inheriting interfaces.
///  A can be a target of events, therefore it implements the
/// [EventTarget] interface.
///
///
///
///    EventTarget
///
///
///
///
///
///    BaseAudioContext
///
///
@JS()
@staticInterop
class BaseAudioContext {
  external factory BaseAudioContext();
}

extension PropsBaseAudioContext on BaseAudioContext {
  AudioDestinationNode get destination => jsu.getProperty(this, 'destination');
  double get sampleRate => jsu.getProperty(this, 'sampleRate');
  double get currentTime => jsu.getProperty(this, 'currentTime');
  AudioContextState get state =>
      AudioContextState.fromValue(jsu.getProperty(this, 'state'));
  AudioWorklet get audioWorklet => jsu.getProperty(this, 'audioWorklet');
  EventHandlerNonNull? get onstatechange =>
      jsu.getProperty(this, 'onstatechange');
  set onstatechange(EventHandlerNonNull? newValue) {
    jsu.setProperty(this, 'onstatechange', newValue);
  }

  AnalyserNode createAnalyser() => jsu.callMethod(this, 'createAnalyser', []);
}

@JS()
@staticInterop
class AudioContext implements BaseAudioContext {
  external factory AudioContext._([AudioContextOptions? contextOptions]);

  factory AudioContext([AudioContextOptions? contextOptions]) =>
      AudioContext._(contextOptions ?? undefined);
}

extension PropsAudioContext on AudioContext {
  Future<void> resume() =>
      jsu.promiseToFuture(jsu.callMethod(this, 'resume', []));

  Future<void> suspend() =>
      jsu.promiseToFuture(jsu.callMethod(this, 'suspend', []));

  Future<void> close() =>
      jsu.promiseToFuture(jsu.callMethod(this, 'close', []));

  MediaStreamAudioSourceNode createMediaStreamSource(MediaStream mediaStream) =>
      jsu.callMethod(this, 'createMediaStreamSource', [mediaStream]);
}

@anonymous
@JS()
@staticInterop
class AudioContextOptions {
  external factory AudioContextOptions(
      {dynamic latencyHint, double? sampleRate});
}

@JS()
@staticInterop
class AudioNode {
  external factory AudioNode();
}

extension PropsAudioNode on AudioNode {
  AudioNode connect(AudioNode destinationNode,
          [int? output = 0, int? input = 0]) =>
      jsu.callMethod(this, 'connect', [destinationNode, output, input]);

  void disconnect([AudioNode? destinationNode, int? output, int? input]) =>
      jsu.callMethod(this, 'disconnect', [destinationNode, output, input]);

  BaseAudioContext get context => jsu.getProperty(this, 'context');
  int get numberOfInputs => jsu.getProperty(this, 'numberOfInputs');
  int get numberOfOutputs => jsu.getProperty(this, 'numberOfOutputs');
  int get channelCount => jsu.getProperty(this, 'channelCount');
  set channelCount(int newValue) {
    jsu.setProperty(this, 'channelCount', newValue);
  }

  ChannelCountMode get channelCountMode =>
      ChannelCountMode.fromValue(jsu.getProperty(this, 'channelCountMode'));
  set channelCountMode(ChannelCountMode newValue) {
    jsu.setProperty(this, 'channelCountMode', newValue.value);
  }

  ChannelInterpretation get channelInterpretation =>
      ChannelInterpretation.fromValue(
          jsu.getProperty(this, 'channelInterpretation'));
  set channelInterpretation(ChannelInterpretation newValue) {
    jsu.setProperty(this, 'channelInterpretation', newValue.value);
  }
}

enum ChannelCountMode {
  max('max'),
  clampedMax('clamped-max'),
  explicit('explicit');

  final String value;
  static ChannelCountMode fromValue(String value) =>
      values.firstWhere((e) => e.value == value);
  static Iterable<ChannelCountMode> fromValues(Iterable<String> values) =>
      values.map(fromValue);
  const ChannelCountMode(this.value);
}

enum ChannelInterpretation {
  speakers('speakers'),
  discrete('discrete');

  final String value;
  static ChannelInterpretation fromValue(String value) =>
      values.firstWhere((e) => e.value == value);
  static Iterable<ChannelInterpretation> fromValues(Iterable<String> values) =>
      values.map(fromValue);
  const ChannelInterpretation(this.value);
}

@JS()
@staticInterop
class AudioDestinationNode implements AudioNode {
  external factory AudioDestinationNode();
}

extension PropsAudioDestinationNode on AudioDestinationNode {
  int get maxChannelCount => jsu.getProperty(this, 'maxChannelCount');
}

@JS()
@staticInterop
class Worklet {
  external factory Worklet();
}

extension PropsWorklet on Worklet {
  Future<void> addModule(String moduleURL, [WorkletOptions? options]) => jsu
      .promiseToFuture(jsu.callMethod(this, 'addModule', [moduleURL, options]));
}

enum RequestCredentials {
  omit('omit'),
  sameOrigin('same-origin'),
  include('include');

  final String value;
  static RequestCredentials fromValue(String value) =>
      values.firstWhere((e) => e.value == value);
  static Iterable<RequestCredentials> fromValues(Iterable<String> values) =>
      values.map(fromValue);
  const RequestCredentials(this.value);
}

@anonymous
@JS()
@staticInterop
class WorkletOptions {
  external factory WorkletOptions._({String? credentials});

  factory WorkletOptions({RequestCredentials? credentials}) => WorkletOptions._(
      credentials: credentials?.value ?? RequestCredentials.sameOrigin.value);
}

extension PropsWorkletOptions on WorkletOptions {
  RequestCredentials get credentials =>
      RequestCredentials.fromValue(jsu.getProperty(this, 'credentials'));
  set credentials(RequestCredentials newValue) {
    jsu.setProperty(this, 'credentials', newValue.value);
  }
}

@JS()
@staticInterop
class AudioWorklet implements Worklet {
  external factory AudioWorklet();
}

@JS()
@staticInterop
class AnalyserNode implements AudioNode {
  external factory AnalyserNode._(BaseAudioContext context,
      [AnalyserOptions? options]);

  factory AnalyserNode(BaseAudioContext context, [AnalyserOptions? options]) =>
      AnalyserNode._(context, options ?? undefined);
}

extension PropsAnalyserNode on AnalyserNode {
  void getFloatFrequencyData(Float32List array) =>
      jsu.callMethod(this, 'getFloatFrequencyData', [array]);

  void getByteFrequencyData(Uint8List array) =>
      jsu.callMethod(this, 'getByteFrequencyData', [array]);

  void getFloatTimeDomainData(Float32List array) =>
      jsu.callMethod(this, 'getFloatTimeDomainData', [array]);

  void getByteTimeDomainData(Uint8List array) =>
      jsu.callMethod(this, 'getByteTimeDomainData', [array]);

  int get fftSize => jsu.getProperty(this, 'fftSize');
  set fftSize(int newValue) {
    jsu.setProperty(this, 'fftSize', newValue);
  }

  int get frequencyBinCount => jsu.getProperty(this, 'frequencyBinCount');
  double get minDecibels => jsu.getProperty(this, 'minDecibels');
  set minDecibels(double newValue) {
    jsu.setProperty(this, 'minDecibels', newValue);
  }

  double get maxDecibels => jsu.getProperty(this, 'maxDecibels');
  set maxDecibels(double newValue) {
    jsu.setProperty(this, 'maxDecibels', newValue);
  }

  double get smoothingTimeConstant =>
      jsu.getProperty(this, 'smoothingTimeConstant');
  set smoothingTimeConstant(double newValue) {
    jsu.setProperty(this, 'smoothingTimeConstant', newValue);
  }
}

@anonymous
@JS()
@staticInterop
class AudioNodeOptions {
  external factory AudioNodeOptions._(
      {int? channelCount,
      String? channelCountMode,
      String? channelInterpretation});

  factory AudioNodeOptions(
          {int? channelCount,
          ChannelCountMode? channelCountMode,
          ChannelInterpretation? channelInterpretation}) =>
      AudioNodeOptions._(
          channelCount: channelCount ?? undefined,
          channelCountMode: channelCountMode?.value ?? undefined,
          channelInterpretation: channelInterpretation?.value ?? undefined);
}

extension PropsAudioNodeOptions on AudioNodeOptions {
  int get channelCount => jsu.getProperty(this, 'channelCount');
  set channelCount(int newValue) {
    jsu.setProperty(this, 'channelCount', newValue);
  }

  ChannelCountMode get channelCountMode =>
      ChannelCountMode.fromValue(jsu.getProperty(this, 'channelCountMode'));
  set channelCountMode(ChannelCountMode newValue) {
    jsu.setProperty(this, 'channelCountMode', newValue.value);
  }

  ChannelInterpretation get channelInterpretation =>
      ChannelInterpretation.fromValue(
          jsu.getProperty(this, 'channelInterpretation'));
  set channelInterpretation(ChannelInterpretation newValue) {
    jsu.setProperty(this, 'channelInterpretation', newValue.value);
  }
}

@anonymous
@JS()
@staticInterop
class AnalyserOptions implements AudioNodeOptions {
  external factory AnalyserOptions._(
      {int? fftSize,
      double? maxDecibels,
      double? minDecibels,
      double? smoothingTimeConstant});

  factory AnalyserOptions(
          {int? fftSize,
          double? maxDecibels,
          double? minDecibels,
          double? smoothingTimeConstant}) =>
      AnalyserOptions._(
          fftSize: fftSize ?? 2048,
          maxDecibels: maxDecibels ?? -30,
          minDecibels: minDecibels ?? -100,
          smoothingTimeConstant: smoothingTimeConstant ?? 0.8);
}

extension PropsAnalyserOptions on AnalyserOptions {
  int get fftSize => jsu.getProperty(this, 'fftSize');
  set fftSize(int newValue) {
    jsu.setProperty(this, 'fftSize', newValue);
  }

  double get maxDecibels => jsu.getProperty(this, 'maxDecibels');
  set maxDecibels(double newValue) {
    jsu.setProperty(this, 'maxDecibels', newValue);
  }

  double get minDecibels => jsu.getProperty(this, 'minDecibels');
  set minDecibels(double newValue) {
    jsu.setProperty(this, 'minDecibels', newValue);
  }

  double get smoothingTimeConstant =>
      jsu.getProperty(this, 'smoothingTimeConstant');
  set smoothingTimeConstant(double newValue) {
    jsu.setProperty(this, 'smoothingTimeConstant', newValue);
  }
}

@JS()
@staticInterop
@anonymous
class MediaStreamTrackEventInit {
  external factory MediaStreamTrackEventInit._({
    dynamic track,
    dynamic bubbles,
    dynamic cancelable,
    dynamic composed,
  });

  factory MediaStreamTrackEventInit({
    required MediaStreamTrack track,
    bool? bubbles,
    bool? cancelable,
    bool? composed,
  }) =>
      MediaStreamTrackEventInit._(
        track: track,
        bubbles: bubbles ?? undefined,
        cancelable: cancelable ?? undefined,
        composed: composed ?? undefined,
      );
}

extension MediaStreamTrackEventInit$Typings on MediaStreamTrackEventInit {
  MediaStreamTrack get track => jsu.getProperty(
        this,
        'track',
      );
  set track(MediaStreamTrack value) {
    jsu.setProperty(
      this,
      'track',
      value,
    );
  }
}

@JS()
@staticInterop
@anonymous
class EventListenerOrEventListenerObject {}

/// Events which indicate that a MediaStream has had tracks added to or removed from the stream through calls to Media Stream API methods. These events are sent to the stream when these changes occur.
@JS()
@staticInterop
class MediaStreamTrackEvent implements Event {
  factory MediaStreamTrackEvent(
    String type,
    MediaStreamTrackEventInit eventInitDict,
  ) =>
      jsu.callConstructor(
        _declaredMediaStreamTrackEvent,
        [
          type,
          eventInitDict,
        ],
      );
}

/*
FieldExternal: 
*/
@JS('MediaStreamTrackEvent')
external Object _declaredMediaStreamTrackEvent;

extension MediaStreamTrackEvent$Typings on MediaStreamTrackEvent {
  MediaStreamTrack get track => jsu.getProperty(
        this,
        'track',
      );
}

enum MediaStreamEventMap<T$ extends Event> {
  addtrack<MediaStreamTrackEvent>(r'addtrack'),
  removetrack<MediaStreamTrackEvent>(r'removetrack');

  const MediaStreamEventMap(this.value);

  final String value;
}

/// A stream of media content. A stream consists of several tracks such as video or audio tracks. Each track is specified as an instance of MediaStreamTrack.
@JS()
@staticInterop
class MediaStream {
  factory MediaStream.$1() => jsu.callConstructor(
        _declaredMediaStream,
        [],
      );

  factory MediaStream.$2(MediaStream stream) => jsu.callConstructor(
        _declaredMediaStream,
        [stream],
      );

  factory MediaStream.$3(List<MediaStreamTrack> tracks) => jsu.callConstructor(
        _declaredMediaStream,
        [tracks],
      );
}

/*
FieldExternal: 
*/
@JS('MediaStream')
external Object _declaredMediaStream;

extension MediaStream$Typings on MediaStream {
  bool get active => jsu.getProperty(
        this,
        'active',
      );
  String get id => jsu.getProperty(
        this,
        'id',
      );

  void addTrack(MediaStreamTrack track) {
    jsu.callMethod(
      this,
      'addTrack',
      [track],
    );
  }

  MediaStream clone() => jsu.callMethod(
        this,
        'clone',
        [],
      );
  List<MediaStreamTrack> getAudioTracks() => (jsu.callMethod(
        this,
        'getAudioTracks',
        [],
      ) as List)
          .cast();
  MediaStreamTrack? getTrackById(String trackId) => jsu.callMethod(
        this,
        'getTrackById',
        [trackId],
      );
  List<MediaStreamTrack> getTracks() => (jsu.callMethod(
        this,
        'getTracks',
        [],
      ) as List)
          .cast();
  List<MediaStreamTrack> getVideoTracks() => (jsu.callMethod(
        this,
        'getVideoTracks',
        [],
      ) as List)
          .cast();
  void removeTrack(MediaStreamTrack track) {
    jsu.callMethod(
      this,
      'removeTrack',
      [track],
    );
  }
}

@JS()
@staticInterop
@anonymous
class MediaStreamConstraints {
  external factory MediaStreamConstraints._({
    dynamic audio,
    dynamic peerIdentity,
    dynamic preferCurrentTab,
    dynamic video,
  });

  factory MediaStreamConstraints({
    Object? audio,
    String? peerIdentity,
    bool? preferCurrentTab,
    Object? video,
  }) =>
      MediaStreamConstraints._(
        audio: audio ?? undefined,
        peerIdentity: peerIdentity ?? undefined,
        preferCurrentTab: preferCurrentTab ?? undefined,
        video: video ?? undefined,
      );
}

extension MediaStreamConstraintsExt on MediaStreamConstraints {
  Object? get audio => jsu.getProperty(
        this,
        'audio',
      );
  set audio(Object? value) {
    jsu.setProperty(
      this,
      'audio',
      value ?? undefined,
    );
  }

  String? get peerIdentity => jsu.getProperty(
        this,
        'peerIdentity',
      );
  set peerIdentity(String? value) {
    jsu.setProperty(
      this,
      'peerIdentity',
      value ?? undefined,
    );
  }

  bool? get preferCurrentTab => jsu.getProperty(
        this,
        'preferCurrentTab',
      );
  set preferCurrentTab(bool? value) {
    jsu.setProperty(
      this,
      'preferCurrentTab',
      value ?? undefined,
    );
  }

  Object? get video => jsu.getProperty(
        this,
        'video',
      );
  set video(Object? value) {
    jsu.setProperty(
      this,
      'video',
      value ?? undefined,
    );
  }
}

@JS()
@staticInterop
class MediaStreamTrack {
  external factory MediaStreamTrack();
}

extension PropsMediaStreamTrack on MediaStreamTrack {
  String get kind => jsu.getProperty(this, 'kind');
  String get id => jsu.getProperty(this, 'id');
  String get label => jsu.getProperty(this, 'label');
  bool get enabled => jsu.getProperty(this, 'enabled');
  set enabled(bool newValue) {
    jsu.setProperty(this, 'enabled', newValue);
  }

  bool get muted => jsu.getProperty(this, 'muted');
  EventHandlerNonNull? get onmute => jsu.getProperty(this, 'onmute');
  set onmute(EventHandlerNonNull? newValue) {
    jsu.setProperty(this, 'onmute', newValue);
  }

  EventHandlerNonNull? get onunmute => jsu.getProperty(this, 'onunmute');
  set onunmute(EventHandlerNonNull? newValue) {
    jsu.setProperty(this, 'onunmute', newValue);
  }

  MediaStreamTrackState get readyState =>
      MediaStreamTrackState.fromValue(jsu.getProperty(this, 'readyState'));
  EventHandlerNonNull? get onended => jsu.getProperty(this, 'onended');
  set onended(EventHandlerNonNull? newValue) {
    jsu.setProperty(this, 'onended', newValue);
  }

  dynamic clone() => jsu.callMethod(this, 'clone', []);

  void stop() => jsu.callMethod(this, 'stop', []);

  MediaTrackCapabilities getCapabilities() =>
      jsu.callMethod(this, 'getCapabilities', []);

  MediaTrackConstraints getConstraints() =>
      jsu.callMethod(this, 'getConstraints', []);

  MediaTrackSettings getSettings() => jsu.callMethod(this, 'getSettings', []);

  Future<void> applyConstraints([MediaTrackConstraints? constraints]) => jsu
      .promiseToFuture(jsu.callMethod(this, 'applyConstraints', [constraints]));

  String get contentHint => jsu.getProperty(this, 'contentHint');
  set contentHint(String newValue) {
    jsu.setProperty(this, 'contentHint', newValue);
  }
}

enum MediaStreamTrackState {
  live('live'),
  ended('ended');

  final String value;
  static MediaStreamTrackState fromValue(String value) =>
      values.firstWhere((e) => e.value == value);
  static Iterable<MediaStreamTrackState> fromValues(Iterable<String> values) =>
      values.map(fromValue);
  const MediaStreamTrackState(this.value);
}

@anonymous
@JS()
@staticInterop
class MediaTrackCapabilities {
  external factory MediaTrackCapabilities({
    ULongRange? sampleRate,
    ULongRange? sampleSize,
    Iterable<bool>? echoCancellation,
    Iterable<bool>? autoGainControl,
    Iterable<bool>? noiseSuppression,
    DoubleRange? latency,
    ULongRange? channelCount,
    String? deviceId,
    String? groupId,
  });
}

extension PropsMediaTrackCapabilities on MediaTrackCapabilities {
  ULongRange get sampleRate => jsu.getProperty(this, 'sampleRate');
  set sampleRate(ULongRange newValue) {
    jsu.setProperty(this, 'sampleRate', newValue);
  }

  ULongRange get sampleSize => jsu.getProperty(this, 'sampleSize');
  set sampleSize(ULongRange newValue) {
    jsu.setProperty(this, 'sampleSize', newValue);
  }

  Iterable<bool> get echoCancellation =>
      jsu.getProperty(this, 'echoCancellation');
  set echoCancellation(Iterable<bool> newValue) {
    jsu.setProperty(this, 'echoCancellation', newValue);
  }

  Iterable<bool> get autoGainControl =>
      jsu.getProperty(this, 'autoGainControl');
  set autoGainControl(Iterable<bool> newValue) {
    jsu.setProperty(this, 'autoGainControl', newValue);
  }

  Iterable<bool> get noiseSuppression =>
      jsu.getProperty(this, 'noiseSuppression');
  set noiseSuppression(Iterable<bool> newValue) {
    jsu.setProperty(this, 'noiseSuppression', newValue);
  }

  DoubleRange get latency => jsu.getProperty(this, 'latency');
  set latency(DoubleRange newValue) {
    jsu.setProperty(this, 'latency', newValue);
  }

  ULongRange get channelCount => jsu.getProperty(this, 'channelCount');
  set channelCount(ULongRange newValue) {
    jsu.setProperty(this, 'channelCount', newValue);
  }

  String get deviceId => jsu.getProperty(this, 'deviceId');
  set deviceId(String newValue) {
    jsu.setProperty(this, 'deviceId', newValue);
  }

  String get groupId => jsu.getProperty(this, 'groupId');
  set groupId(String newValue) {
    jsu.setProperty(this, 'groupId', newValue);
  }
}

///  The dictionary is used to return the current values configured
/// for each of a [MediaStreamTrack]'s settings. These values will
/// adhere as closely as possible to any constraints previously
/// described using a [MediaTrackConstraints] object and set using
/// [applyConstraints()], and will adhere to the default constraints
/// for any properties whose constraints haven't been changed, or
/// whose customized constraints couldn't be matched.
///  To learn more about how constraints and settings work, see
/// Capabilities, constraints, and settings.
@anonymous
@JS()
@staticInterop
class MediaTrackSettings {
  external factory MediaTrackSettings({
    int? sampleRate,
    int? sampleSize,
    bool? echoCancellation,
    bool? autoGainControl,
    bool? noiseSuppression,
    double? latency,
    int? channelCount,
    String? deviceId,
    String? groupId,
  });
}

extension PropsMediaTrackSettings on MediaTrackSettings {
  int get sampleRate => jsu.getProperty(this, 'sampleRate');
  set sampleRate(int newValue) {
    jsu.setProperty(this, 'sampleRate', newValue);
  }

  int get sampleSize => jsu.getProperty(this, 'sampleSize');
  set sampleSize(int newValue) {
    jsu.setProperty(this, 'sampleSize', newValue);
  }

  bool get echoCancellation => jsu.getProperty(this, 'echoCancellation');
  set echoCancellation(bool newValue) {
    jsu.setProperty(this, 'echoCancellation', newValue);
  }

  bool get autoGainControl => jsu.getProperty(this, 'autoGainControl');
  set autoGainControl(bool newValue) {
    jsu.setProperty(this, 'autoGainControl', newValue);
  }

  bool get noiseSuppression => jsu.getProperty(this, 'noiseSuppression');
  set noiseSuppression(bool newValue) {
    jsu.setProperty(this, 'noiseSuppression', newValue);
  }

  double get latency => jsu.getProperty(this, 'latency');
  set latency(double newValue) {
    jsu.setProperty(this, 'latency', newValue);
  }

  int get channelCount => jsu.getProperty(this, 'channelCount');
  set channelCount(int newValue) {
    jsu.setProperty(this, 'channelCount', newValue);
  }

  String get deviceId => jsu.getProperty(this, 'deviceId');
  set deviceId(String newValue) {
    jsu.setProperty(this, 'deviceId', newValue);
  }

  String get groupId => jsu.getProperty(this, 'groupId');
  set groupId(String newValue) {
    jsu.setProperty(this, 'groupId', newValue);
  }
}

@JS()
@staticInterop
class AudioParam {
  external factory AudioParam();
}

@JS()
@staticInterop
class AudioParamMap extends JsMap<AudioParam, String> {
  external factory AudioParamMap();
}

@JS()
@staticInterop
class AudioWorkletNode implements AudioNode {
  external factory AudioWorkletNode._(BaseAudioContext context, String name,
      [AudioWorkletNodeOptions? options]);

  factory AudioWorkletNode(BaseAudioContext context, String name,
          [AudioWorkletNodeOptions? options]) =>
      AudioWorkletNode._(context, name, options ?? undefined);
}

extension PropsAudioWorkletNode on AudioWorkletNode {
  MessagePort get port => jsu.getProperty(this, 'port');
  EventHandlerNonNull? get onprocessorerror =>
      jsu.getProperty(this, 'onprocessorerror');
  set onprocessorerror(EventHandlerNonNull? newValue) {
    jsu.setProperty(this, 'onprocessorerror', newValue);
  }
}

@JS()
@staticInterop
class MessagePort {
  external factory MessagePort();
}

extension PropsMessagePort on MessagePort {
  void postMessage(dynamic message, Iterable<dynamic> transfer) =>
      jsu.callMethod(this, 'postMessage', [message, transfer]);

  void start() => jsu.callMethod(this, 'start', []);

  void close() => jsu.callMethod(this, 'close', []);

  EventHandlerNonNull? get onmessage => jsu.getProperty(this, 'onmessage');
  set onmessage(EventHandlerNonNull? newValue) {
    jsu.setProperty(this, 'onmessage', newValue);
  }

  EventHandlerNonNull? get onmessageerror =>
      jsu.getProperty(this, 'onmessageerror');
  set onmessageerror(EventHandlerNonNull? newValue) {
    jsu.setProperty(this, 'onmessageerror', newValue);
  }
}

@anonymous
@JS()
@staticInterop
class AudioWorkletNodeOptions implements AudioNodeOptions {
  external factory AudioWorkletNodeOptions._(
      {int? numberOfInputs,
      int? numberOfOutputs,
      Iterable<int>? outputChannelCount,
      dynamic parameterData,
      dynamic processorOptions});

  factory AudioWorkletNodeOptions(
          {int? numberOfInputs,
          int? numberOfOutputs,
          Iterable<int>? outputChannelCount,
          dynamic parameterData,
          dynamic processorOptions}) =>
      AudioWorkletNodeOptions._(
          numberOfInputs: numberOfInputs ?? 1,
          numberOfOutputs: numberOfOutputs ?? 1,
          outputChannelCount: outputChannelCount ?? undefined,
          parameterData: parameterData ?? undefined,
          processorOptions: processorOptions ?? undefined);
}

extension PropsAudioWorkletNodeOptions on AudioWorkletNodeOptions {
  int get numberOfInputs => jsu.getProperty(this, 'numberOfInputs');
  set numberOfInputs(int newValue) {
    jsu.setProperty(this, 'numberOfInputs', newValue);
  }

  int get numberOfOutputs => jsu.getProperty(this, 'numberOfOutputs');
  set numberOfOutputs(int newValue) {
    jsu.setProperty(this, 'numberOfOutputs', newValue);
  }

  Iterable<int> get outputChannelCount =>
      jsu.getProperty(this, 'outputChannelCount');
  set outputChannelCount(Iterable<int> newValue) {
    jsu.setProperty(this, 'outputChannelCount', newValue);
  }

  dynamic get parameterData => jsu.getProperty(this, 'parameterData');
  set parameterData(dynamic newValue) {
    jsu.setProperty(this, 'parameterData', newValue);
  }

  dynamic get processorOptions => jsu.getProperty(this, 'processorOptions');
  set processorOptions(dynamic newValue) {
    jsu.setProperty(this, 'processorOptions', newValue);
  }
}

@JS()
@staticInterop
class MediaDevices {
  external factory MediaDevices();
}

extension PropsMediaDevices on MediaDevices {
  EventHandlerNonNull? get ondevicechange =>
      jsu.getProperty(this, 'ondevicechange');
  set ondevicechange(EventHandlerNonNull? newValue) {
    jsu.setProperty(this, 'ondevicechange', newValue);
  }

  Future<Iterable<MediaDeviceInfo>> enumerateDevices() =>
      jsu.promiseToFuture(jsu.callMethod(this, 'enumerateDevices', []));

  MediaTrackSupportedConstraints getSupportedConstraints() =>
      jsu.callMethod(this, 'getSupportedConstraints', []);

  Future<MediaStream> getUserMedia([MediaStreamConstraints? constraints]) =>
      jsu.promiseToFuture(jsu.callMethod(this, 'getUserMedia', [constraints]));
}

///  The interface contains information that describes a single media
/// input or output device.
///  The list of devices obtained by calling
/// [navigator.mediaDevices.enumerateDevices()] is an array of
/// objects, one per media device.
@JS()
@staticInterop
class MediaDeviceInfo {
  external factory MediaDeviceInfo();
}

extension PropsMediaDeviceInfo on MediaDeviceInfo {
  String get deviceId => jsu.getProperty(this, 'deviceId');
  MediaDeviceKind get kind =>
      MediaDeviceKind.fromValue(jsu.getProperty(this, 'kind'));
  String get label => jsu.getProperty(this, 'label');
  String get groupId => jsu.getProperty(this, 'groupId');
  dynamic toJSON() => jsu.callMethod(this, 'toJSON', []);
}

enum MediaDeviceKind {
  audioinput('audioinput'),
  audiooutput('audiooutput'),
  videoinput('videoinput');

  final String value;
  static MediaDeviceKind fromValue(String value) =>
      values.firstWhere((e) => e.value == value);
  static Iterable<MediaDeviceKind> fromValues(Iterable<String> values) =>
      values.map(fromValue);
  const MediaDeviceKind(this.value);
}

@anonymous
@JS()
@staticInterop
class MediaTrackSupportedConstraints {
  external factory MediaTrackSupportedConstraints._({
    bool? sampleRate,
    bool? sampleSize,
    bool? echoCancellation,
    bool? autoGainControl,
    bool? noiseSuppression,
    bool? latency,
    bool? channelCount,
    bool? deviceId,
    bool? groupId,
  });

  factory MediaTrackSupportedConstraints(
          {bool? sampleRate,
          bool? sampleSize,
          bool? echoCancellation,
          bool? autoGainControl,
          bool? noiseSuppression,
          bool? latency,
          bool? channelCount,
          bool? deviceId,
          bool? groupId}) =>
      MediaTrackSupportedConstraints._(
          sampleRate: sampleRate ?? true,
          sampleSize: sampleSize ?? true,
          echoCancellation: echoCancellation ?? true,
          autoGainControl: autoGainControl ?? true,
          noiseSuppression: noiseSuppression ?? true,
          latency: latency ?? true,
          channelCount: channelCount ?? true,
          deviceId: deviceId ?? true,
          groupId: groupId ?? true);
}

extension PropsMediaTrackSupportedConstraints
    on MediaTrackSupportedConstraints {
  bool get sampleRate => jsu.getProperty(this, 'sampleRate');
  set sampleRate(bool newValue) {
    jsu.setProperty(this, 'sampleRate', newValue);
  }

  bool get sampleSize => jsu.getProperty(this, 'sampleSize');
  set sampleSize(bool newValue) {
    jsu.setProperty(this, 'sampleSize', newValue);
  }

  bool get echoCancellation => jsu.getProperty(this, 'echoCancellation');
  set echoCancellation(bool newValue) {
    jsu.setProperty(this, 'echoCancellation', newValue);
  }

  bool get autoGainControl => jsu.getProperty(this, 'autoGainControl');
  set autoGainControl(bool newValue) {
    jsu.setProperty(this, 'autoGainControl', newValue);
  }

  bool get noiseSuppression => jsu.getProperty(this, 'noiseSuppression');
  set noiseSuppression(bool newValue) {
    jsu.setProperty(this, 'noiseSuppression', newValue);
  }

  bool get latency => jsu.getProperty(this, 'latency');
  set latency(bool newValue) {
    jsu.setProperty(this, 'latency', newValue);
  }

  bool get channelCount => jsu.getProperty(this, 'channelCount');
  set channelCount(bool newValue) {
    jsu.setProperty(this, 'channelCount', newValue);
  }

  bool get deviceId => jsu.getProperty(this, 'deviceId');
  set deviceId(bool newValue) {
    jsu.setProperty(this, 'deviceId', newValue);
  }

  bool get groupId => jsu.getProperty(this, 'groupId');
  set groupId(bool newValue) {
    jsu.setProperty(this, 'groupId', newValue);
  }
}

@JS()
external Window get window;

@JS()
@staticInterop
class Window {
  external factory Window();
}

extension PropsWindow on Window {
  Navigator get navigator => jsu.getProperty(this, 'navigator');
}

@JS()
@staticInterop
class Navigator {
  external factory Navigator();
}

extension PropsNavigator on Navigator {
  MediaDevices get mediaDevices => jsu.getProperty(this, 'mediaDevices');
}

@JS()
@staticInterop
class MessageEvent implements Event {
  external factory MessageEvent._(String type,
      [MessageEventInit? eventInitDict]);

  factory MessageEvent(String type, [MessageEventInit? eventInitDict]) =>
      MessageEvent._(type, eventInitDict ?? undefined);
}

extension PropsMessageEvent on MessageEvent {
  dynamic get data => jsu.getProperty(this, 'data');
  String get origin => jsu.getProperty(this, 'origin');
  String get lastEventId => jsu.getProperty(this, 'lastEventId');
  dynamic get source => jsu.getProperty(this, 'source');
  Iterable<MessagePort> get ports => jsu.getProperty(this, 'ports');
  void initMessageEvent(String type,
          [bool? bubbles = false,
          bool? cancelable = false,
          dynamic data,
          String? origin = '',
          String? lastEventId = '',
          dynamic source,
          Iterable<MessagePort>? ports = const []]) =>
      jsu.callMethod(this, 'initMessageEvent', [
        type,
        bubbles,
        cancelable,
        data,
        origin,
        lastEventId,
        source,
        ports
      ]);
}

@anonymous
@JS()
@staticInterop
class MessageEventInit implements EventInit {
  external factory MessageEventInit._(
      {dynamic data,
      String? origin,
      String? lastEventId,
      dynamic source,
      Iterable<MessagePort>? ports});

  factory MessageEventInit(
          {dynamic data,
          String? origin,
          String? lastEventId,
          dynamic source,
          Iterable<MessagePort>? ports}) =>
      MessageEventInit._(
          data: data ?? undefined,
          origin: origin ?? '',
          lastEventId: lastEventId ?? '',
          source: source ?? undefined,
          ports: ports ?? const []);
}

extension PropsMessageEventInit on MessageEventInit {
  dynamic get data => jsu.getProperty(this, 'data');
  set data(dynamic newValue) {
    jsu.setProperty(this, 'data', newValue);
  }

  String get origin => jsu.getProperty(this, 'origin');
  set origin(String newValue) {
    jsu.setProperty(this, 'origin', newValue);
  }

  String get lastEventId => jsu.getProperty(this, 'lastEventId');
  set lastEventId(String newValue) {
    jsu.setProperty(this, 'lastEventId', newValue);
  }

  dynamic get source => jsu.getProperty(this, 'source');
  set source(dynamic newValue) {
    jsu.setProperty(this, 'source', newValue);
  }

  Iterable<MessagePort> get ports => jsu.getProperty(this, 'ports');
  set ports(Iterable<MessagePort> newValue) {
    jsu.setProperty(this, 'ports', newValue);
  }
}

@JS()
@staticInterop
class MediaRecorder {
  external factory MediaRecorder._(MediaStream stream,
      [MediaRecorderOptions? options]);

  factory MediaRecorder(MediaStream stream, [MediaRecorderOptions? options]) =>
      MediaRecorder._(stream, options ?? undefined);
  external static bool isTypeSupported(String type);
}

extension PropsMediaRecorder on MediaRecorder {
  MediaStream get stream => jsu.getProperty(this, 'stream');
  String get mimeType => jsu.getProperty(this, 'mimeType');
  RecordingState get state =>
      RecordingState.fromValue(jsu.getProperty(this, 'state'));
  EventHandlerNonNull? get onstart => jsu.getProperty(this, 'onstart');
  set onstart(EventHandlerNonNull? newValue) {
    jsu.setProperty(this, 'onstart', newValue);
  }

  EventHandlerNonNull? get onstop => jsu.getProperty(this, 'onstop');
  set onstop(EventHandlerNonNull? newValue) {
    jsu.setProperty(this, 'onstop', newValue);
  }

  EventHandlerNonNull? get ondataavailable =>
      jsu.getProperty(this, 'ondataavailable');
  set ondataavailable(EventHandlerNonNull? newValue) {
    jsu.setProperty(this, 'ondataavailable', newValue);
  }

  EventHandlerNonNull? get onpause => jsu.getProperty(this, 'onpause');
  set onpause(EventHandlerNonNull? newValue) {
    jsu.setProperty(this, 'onpause', newValue);
  }

  EventHandlerNonNull? get onresume => jsu.getProperty(this, 'onresume');
  set onresume(EventHandlerNonNull? newValue) {
    jsu.setProperty(this, 'onresume', newValue);
  }

  EventHandlerNonNull? get onerror => jsu.getProperty(this, 'onerror');
  set onerror(EventHandlerNonNull? newValue) {
    jsu.setProperty(this, 'onerror', newValue);
  }

  int get videoBitsPerSecond => jsu.getProperty(this, 'videoBitsPerSecond');
  int get audioBitsPerSecond => jsu.getProperty(this, 'audioBitsPerSecond');
  BitrateMode get audioBitrateMode =>
      BitrateMode.fromValue(jsu.getProperty(this, 'audioBitrateMode'));
  void start([int? timeslice]) => jsu.callMethod(this, 'start', [timeslice]);

  void stop() => jsu.callMethod(this, 'stop', []);

  void pause() => jsu.callMethod(this, 'pause', []);

  void resume() => jsu.callMethod(this, 'resume', []);

  void requestData() => jsu.callMethod(this, 'requestData', []);
}

@anonymous
@JS()
@staticInterop
class MediaRecorderOptions {
  external factory MediaRecorderOptions._(
      {String? mimeType,
      int? audioBitsPerSecond,
      int? videoBitsPerSecond,
      int? bitsPerSecond,
      String? audioBitrateMode});

  factory MediaRecorderOptions(
          {String? mimeType,
          int? audioBitsPerSecond,
          int? videoBitsPerSecond,
          int? bitsPerSecond,
          BitrateMode? audioBitrateMode}) =>
      MediaRecorderOptions._(
          mimeType: mimeType ?? '',
          audioBitsPerSecond: audioBitsPerSecond ?? undefined,
          videoBitsPerSecond: videoBitsPerSecond ?? undefined,
          bitsPerSecond: bitsPerSecond ?? undefined,
          audioBitrateMode:
              audioBitrateMode?.value ?? BitrateMode.variable.value);
}

extension PropsMediaRecorderOptions on MediaRecorderOptions {
  String get mimeType => jsu.getProperty(this, 'mimeType');
  set mimeType(String newValue) {
    jsu.setProperty(this, 'mimeType', newValue);
  }

  int get audioBitsPerSecond => jsu.getProperty(this, 'audioBitsPerSecond');
  set audioBitsPerSecond(int newValue) {
    jsu.setProperty(this, 'audioBitsPerSecond', newValue);
  }

  int get videoBitsPerSecond => jsu.getProperty(this, 'videoBitsPerSecond');
  set videoBitsPerSecond(int newValue) {
    jsu.setProperty(this, 'videoBitsPerSecond', newValue);
  }

  int get bitsPerSecond => jsu.getProperty(this, 'bitsPerSecond');
  set bitsPerSecond(int newValue) {
    jsu.setProperty(this, 'bitsPerSecond', newValue);
  }

  BitrateMode get audioBitrateMode =>
      BitrateMode.fromValue(jsu.getProperty(this, 'audioBitrateMode'));
  set audioBitrateMode(BitrateMode newValue) {
    jsu.setProperty(this, 'audioBitrateMode', newValue.value);
  }
}

enum BitrateMode {
  constant('constant'),
  variable('variable');

  final String value;
  static BitrateMode fromValue(String value) =>
      values.firstWhere((e) => e.value == value);
  static Iterable<BitrateMode> fromValues(Iterable<String> values) =>
      values.map(fromValue);
  const BitrateMode(this.value);
}

enum RecordingState {
  inactive('inactive'),
  recording('recording'),
  paused('paused');

  final String value;
  static RecordingState fromValue(String value) =>
      values.firstWhere((e) => e.value == value);
  static Iterable<RecordingState> fromValues(Iterable<String> values) =>
      values.map(fromValue);
  const RecordingState(this.value);
}

@JS()
@staticInterop
class MediaStreamAudioSourceNode implements AudioNode {
  external factory MediaStreamAudioSourceNode(
      AudioContext context, MediaStreamAudioSourceOptions options);
}

extension PropsMediaStreamAudioSourceNode on MediaStreamAudioSourceNode {
  MediaStream get mediaStream => jsu.getProperty(this, 'mediaStream');
}

@anonymous
@JS()
@staticInterop
class MediaStreamAudioSourceOptions {
  external factory MediaStreamAudioSourceOptions(
      {required MediaStream mediaStream});
}

extension PropsMediaStreamAudioSourceOptions on MediaStreamAudioSourceOptions {
  MediaStream get mediaStream => jsu.getProperty(this, 'mediaStream');
  set mediaStream(MediaStream newValue) {
    jsu.setProperty(this, 'mediaStream', newValue);
  }
}

typedef ConstrainBoolean = Object;
typedef ConstrainDOMString = Object;
typedef ConstrainDouble = Object;
typedef ConstrainULong = Object;

@JS()
@staticInterop
@anonymous
class MediaTrackConstraintSet {
  external factory MediaTrackConstraintSet._({
    dynamic aspectRatio,
    dynamic autoGainControl,
    dynamic channelCount,
    dynamic deviceId,
    dynamic displaySurface,
    dynamic echoCancellation,
    dynamic facingMode,
    dynamic frameRate,
    dynamic groupId,
    dynamic height,
    dynamic noiseSuppression,
    dynamic sampleRate,
    dynamic sampleSize,
    dynamic width,
  });

  factory MediaTrackConstraintSet({
    ConstrainDouble? aspectRatio,
    ConstrainBoolean? autoGainControl,
    double? channelCount,
    ConstrainDOMString? deviceId,
    ConstrainDOMString? displaySurface,
    ConstrainBoolean? echoCancellation,
    ConstrainDOMString? facingMode,
    ConstrainDouble? frameRate,
    ConstrainDOMString? groupId,
    double? height,
    ConstrainBoolean? noiseSuppression,
    double? sampleRate,
    double? sampleSize,
    double? width,
  }) =>
      MediaTrackConstraintSet._(
        aspectRatio: aspectRatio ?? undefined ?? undefined,
        autoGainControl: autoGainControl ?? undefined ?? undefined,
        channelCount: channelCount ?? undefined,
        deviceId: deviceId ?? undefined ?? undefined,
        displaySurface: displaySurface ?? undefined ?? undefined,
        echoCancellation: echoCancellation ?? undefined ?? undefined,
        facingMode: facingMode ?? undefined ?? undefined,
        frameRate: frameRate ?? undefined ?? undefined,
        groupId: groupId ?? undefined ?? undefined,
        height: height ?? undefined,
        noiseSuppression: noiseSuppression ?? undefined ?? undefined,
        sampleRate: sampleRate ?? undefined,
        sampleSize: sampleSize ?? undefined,
        width: width ?? undefined,
      );
}

extension MediaTrackConstraintSet$Typings on MediaTrackConstraintSet {
  ConstrainDouble? get aspectRatio => jsu.getProperty(
        this,
        'aspectRatio',
      );
  set aspectRatio(ConstrainDouble? value) {
    jsu.setProperty(
      this,
      'aspectRatio',
      value ?? undefined ?? undefined,
    );
  }

  ConstrainBoolean? get autoGainControl => jsu.getProperty(
        this,
        'autoGainControl',
      );
  set autoGainControl(ConstrainBoolean? value) {
    jsu.setProperty(
      this,
      'autoGainControl',
      value ?? undefined ?? undefined,
    );
  }

  double? get channelCount => jsu.getProperty(
        this,
        'channelCount',
      );
  set channelCount(double? value) {
    jsu.setProperty(
      this,
      'channelCount',
      value ?? undefined,
    );
  }

  ConstrainDOMString? get deviceId => jsu.getProperty(
        this,
        'deviceId',
      );
  set deviceId(ConstrainDOMString? value) {
    jsu.setProperty(
      this,
      'deviceId',
      value ?? undefined ?? undefined,
    );
  }

  ConstrainDOMString? get displaySurface => jsu.getProperty(
        this,
        'displaySurface',
      );
  set displaySurface(ConstrainDOMString? value) {
    jsu.setProperty(
      this,
      'displaySurface',
      value ?? undefined ?? undefined,
    );
  }

  ConstrainBoolean? get echoCancellation => jsu.getProperty(
        this,
        'echoCancellation',
      );
  set echoCancellation(ConstrainBoolean? value) {
    jsu.setProperty(
      this,
      'echoCancellation',
      value ?? undefined ?? undefined,
    );
  }

  ConstrainDOMString? get facingMode => jsu.getProperty(
        this,
        'facingMode',
      );
  set facingMode(ConstrainDOMString? value) {
    jsu.setProperty(
      this,
      'facingMode',
      value ?? undefined ?? undefined,
    );
  }

  ConstrainDouble? get frameRate => jsu.getProperty(
        this,
        'frameRate',
      );
  set frameRate(ConstrainDouble? value) {
    jsu.setProperty(
      this,
      'frameRate',
      value ?? undefined ?? undefined,
    );
  }

  ConstrainDOMString? get groupId => jsu.getProperty(
        this,
        'groupId',
      );
  set groupId(ConstrainDOMString? value) {
    jsu.setProperty(
      this,
      'groupId',
      value ?? undefined ?? undefined,
    );
  }

  double? get height => jsu.getProperty(
        this,
        'height',
      );
  set height(double? value) {
    jsu.setProperty(
      this,
      'height',
      value ?? undefined,
    );
  }

  ConstrainBoolean? get noiseSuppression => jsu.getProperty(
        this,
        'noiseSuppression',
      );
  set noiseSuppression(ConstrainBoolean? value) {
    jsu.setProperty(
      this,
      'noiseSuppression',
      value ?? undefined ?? undefined,
    );
  }

  double? get sampleRate => jsu.getProperty(
        this,
        'sampleRate',
      );
  set sampleRate(double? value) {
    jsu.setProperty(
      this,
      'sampleRate',
      value ?? undefined,
    );
  }

  double? get sampleSize => jsu.getProperty(
        this,
        'sampleSize',
      );
  set sampleSize(double? value) {
    jsu.setProperty(
      this,
      'sampleSize',
      value ?? undefined,
    );
  }

  double? get width => jsu.getProperty(
        this,
        'width',
      );
  set width(double? value) {
    jsu.setProperty(
      this,
      'width',
      value ?? undefined,
    );
  }
}

@JS()
@staticInterop
@anonymous
class MediaTrackConstraints implements MediaTrackConstraintSet {
  external factory MediaTrackConstraints._({
    dynamic advanced,
    dynamic aspectRatio,
    dynamic autoGainControl,
    dynamic channelCount,
    dynamic deviceId,
    dynamic displaySurface,
    dynamic echoCancellation,
    dynamic facingMode,
    dynamic frameRate,
    dynamic groupId,
    dynamic height,
    dynamic noiseSuppression,
    dynamic sampleRate,
    dynamic sampleSize,
    dynamic width,
  });

  factory MediaTrackConstraints({
    List<MediaTrackConstraintSet>? advanced,
    ConstrainDouble? aspectRatio,
    ConstrainBoolean? autoGainControl,
    double? channelCount,
    ConstrainDOMString? deviceId,
    ConstrainDOMString? displaySurface,
    ConstrainBoolean? echoCancellation,
    ConstrainDOMString? facingMode,
    ConstrainDouble? frameRate,
    ConstrainDOMString? groupId,
    double? height,
    ConstrainBoolean? noiseSuppression,
    double? sampleRate,
    double? sampleSize,
    double? width,
  }) =>
      MediaTrackConstraints._(
        advanced: advanced ?? undefined,
        aspectRatio: aspectRatio ?? undefined ?? undefined,
        autoGainControl: autoGainControl ?? undefined ?? undefined,
        channelCount: channelCount ?? undefined,
        deviceId: deviceId ?? undefined ?? undefined,
        displaySurface: displaySurface ?? undefined ?? undefined,
        echoCancellation: echoCancellation ?? undefined ?? undefined,
        facingMode: facingMode ?? undefined ?? undefined,
        frameRate: frameRate ?? undefined ?? undefined,
        groupId: groupId ?? undefined ?? undefined,
        height: height ?? undefined,
        noiseSuppression: noiseSuppression ?? undefined ?? undefined,
        sampleRate: sampleRate ?? undefined,
        sampleSize: sampleSize ?? undefined,
        width: width ?? undefined,
      );
}

extension MediaTrackConstraints$Typings on MediaTrackConstraints {
  List<MediaTrackConstraintSet>? get advanced => (jsu.getProperty(
        this,
        'advanced',
      ) as List?)
          ?.cast();
  set advanced(List<MediaTrackConstraintSet>? value) {
    jsu.setProperty(
      this,
      'advanced',
      value ?? undefined,
    );
  }
}
