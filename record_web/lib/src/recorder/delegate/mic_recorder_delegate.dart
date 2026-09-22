import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:record_web/src/encoder/encoder.dart';
import 'package:record_web/src/encoder/pcm_encoder.dart';
import 'package:record_web/src/encoder/wav_encoder.dart';
import 'package:record_web/src/recorder/delegate/recorder_delegate.dart';
import 'package:record_web/src/recorder/recorder.dart';
import 'package:web/web.dart' as web;

/// Records WAVE and PCM through an AudioWorklet, to a file or a stream.
class MicRecorderDelegate extends RecorderDelegate {
  final OnStateChanged onStateChanged;
  @override
  final void Function(RecordConfig)? onConfigChanged;

  // Media stream get from getUserMedia
  web.MediaStream? _mediaStream;
  web.AudioContext? _context;
  web.AudioWorkletNode? _workletNode;
  web.MediaStreamAudioSourceNode? _source;

  StreamController<Uint8List>? _recordStreamCtrl;
  Encoder? _encoder;
  RecordConfig? _config;
  // Amplitude
  double _maxAmplitude = kMinAmplitude;
  double _amplitude = kMinAmplitude;

  MicRecorderDelegate({required this.onStateChanged, this.onConfigChanged});

  @override
  Future<void> dispose() => _reset();

  @override
  Future<Amplitude> getAmplitude() async {
    return Amplitude(current: _amplitude, max: _maxAmplitude);
  }

  @override
  Future<bool> isPaused() async {
    return _context?.state == 'suspended';
  }

  @override
  Future<bool> isRecording() async {
    final context = _context;
    return context != null && context.state != 'closed';
  }

  @override
  Future<void> pause() async {
    final context = _context;
    if (context != null && context.state == 'running') {
      await context.suspend().toDart;
      onStateChanged(RecordState.pause);
    }
  }

  @override
  Future<void> resume() async {
    final context = _context;
    if (context == null || context.state != 'suspended') return;

    // A removed device ends the paused track: move back to it or to the default one, or stay paused to retry.
    if (isSourceDead(_mediaStream) && !await reattach()) {
      throw const RecordResumeNoDeviceException();
    }

    await context.resume().toDart;

    // Chromium disconnects the worklet after a long pause (> 12~15 s).
    if (_source case final source?) wireSource(source);

    onStateChanged(RecordState.record);
  }

  @override
  web.AudioContext? get audioContext => _context;

  @override
  web.MediaStream? get mediaStream => _mediaStream;

  @override
  web.MediaStreamAudioSourceNode? get source => _source;

  @override
  RecordConfig? get recordConfig => _config;

  @override
  void onSourceSwapped(
    web.MediaStreamAudioSourceNode source,
    web.MediaStream mediaStream,
    RecordConfig config,
  ) {
    _source = source;
    _mediaStream = mediaStream;
    _config = config;
  }

  @override
  Future<void> start(RecordConfig config, {required String path}) {
    return _start(config);
  }

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    // Not awaited: an unlistened controller never completes its close.
    unawaited(_recordStreamCtrl?.close());
    _recordStreamCtrl = StreamController<Uint8List>();

    try {
      await _start(config, isStream: true);
    } catch (err) {
      debugPrint(err.toString());
      unawaited(_recordStreamCtrl?.close());
      _recordStreamCtrl = null;
      rethrow;
    }

    return _recordStreamCtrl!.stream;
  }

  @override
  Future<String?> stop() async {
    if (takeRouteStop() case final stopped?) return stopped;

    await _reset(resetEncoder: false);

    final blob = _encoder?.finish();
    _encoder?.cleanup();
    _encoder = null;

    onStateChanged(RecordState.stop);

    return blob != null ? web.URL.createObjectURL(blob) : null;
  }

  Future<void> _start(RecordConfig config, {bool isStream = false}) async {
    final mediaStream = await initMediaStream(config);

    // The worklet resamples and remixes to the requested format.
    final effectiveConfig = adjustConfig(
      mediaStream,
      config,
      canConvert: true,
      onConfigChanged: onConfigChanged,
    );
    final context = effectiveConfig.context;
    config = effectiveConfig.config;

    final source = context.createMediaStreamSource(mediaStream);

    final workletNode = await _createWorkletNode(context, config);

    if (!isStream) {
      _encoder?.cleanup();

      if (config.encoder == AudioEncoder.wav) {
        _encoder = WavEncoder(
          sampleRate: config.sampleRate.toInt(),
          numChannels: config.numChannels,
        );
      } else if (config.encoder == AudioEncoder.pcm16bits) {
        _encoder = PcmEncoder();
      }
    }

    if (isStream) {
      workletNode.port.onmessage =
          ((web.MessageEvent event) => _onMessageStream(event)).toJS;
    } else {
      workletNode.port.onmessage = ((web.MessageEvent event) => _onMessage(
        event,
      )).toJS;
    }

    _source = source;
    _workletNode = workletNode;
    _context = context;
    _mediaStream = mediaStream;
    _config = config;
    requestedDevice = config.device;

    wireSource(source);
    listenRouteChange(mediaStream);

    onStateChanged(RecordState.record);
  }

  /// Feeds [source] to the worklet; connecting twice is a no-op.
  @override
  void wireSource(web.MediaStreamAudioSourceNode source) {
    final context = _context;
    final workletNode = _workletNode;
    if (context == null || workletNode == null) return;

    source.connect(workletNode)?.connect(context.destination);
  }

  Future<web.AudioWorkletNode> _createWorkletNode(
    web.AudioContext context,
    RecordConfig config,
  ) async {
    await context.audioWorklet
        .addModule('assets/packages/record_web/assets/js/record.worklet.js')
        .toDart;

    return web.AudioWorkletNode(
      context,
      'recorder.worklet',
      web.AudioWorkletNodeOptions(
        parameterData:
            {
                  'numChannels'.toJS: config.numChannels.toJS,
                  'sampleRate'.toJS: config.sampleRate.toJS,
                  'streamBufferSize'.toJS:
                      (config.streamBufferSize ?? 2048).toJS,
                }.jsify()!
                as JSObject,
      ),
    );
  }

  void _onMessage(web.MessageEvent event) {
    // `data` is a int 16 array containing audio samples
    final output = (event.data as JSInt16Array?)?.toDart;

    if (output case final output?) {
      _encoder?.encode(output);
      _updateAmplitude(output);
    }
  }

  void _onMessageStream(web.MessageEvent event) {
    // `data` is a int 16 array containing audio samples
    final output = (event.data as JSInt16Array?)?.toDart;

    if (output case final output?) {
      _recordStreamCtrl?.add(
        output.buffer.asUint8List(output.offsetInBytes, output.lengthInBytes),
      );
      _updateAmplitude(output);
    }
  }

  void _updateAmplitude(Int16List data) {
    var maxSample = kMinAmplitude;

    for (var i = 0; i < data.length; i++) {
      var curSample = data[i].abs();
      if (curSample > maxSample) {
        maxSample = curSample.toDouble();
      }
    }

    _amplitude = 20 * (log(maxSample / 32767) / ln10);

    if (_amplitude > _maxAmplitude) {
      _maxAmplitude = _amplitude;
    }
  }

  Future<void> _reset({bool resetEncoder = true}) async {
    // Clear the fields before awaiting `resetContext`, so an in-flight swap sees the take ended.
    final context = _context;
    final mediaStream = _mediaStream;
    _mediaStream = null;
    _context = null;
    _config = null;
    await resetContext(context, mediaStream);

    if (resetEncoder) {
      _encoder?.cleanup();
      _encoder = null;
    }

    _maxAmplitude = kMinAmplitude;
    _amplitude = kMinAmplitude;

    unawaited(_recordStreamCtrl?.close());
    _recordStreamCtrl = null;
  }
}
