import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:record_web/encoder/encoder.dart';
import 'package:record_web/encoder/pcm_encoder.dart';
import 'package:record_web/encoder/wav_encoder.dart';
import 'package:record_web/recorder/delegate/recorder_delegate.dart';
import 'package:record_web/recorder/recorder.dart';
import 'package:web/web.dart' as web;

class MicRecorderDelegate extends RecorderDelegate {
  final OnStateChanged onStateChanged;

  // Media stream get from getUserMedia
  web.MediaStream? _mediaStream;
  web.AudioContext? _context;
  web.AudioWorkletNode? _workletNode;
  web.MediaStreamAudioSourceNode? _source;

  StreamController<Uint8List>? _recordStreamCtrl;
  Encoder? _encoder;
  // Amplitude
  double _maxAmplitude = kMinAmplitude;
  double _amplitude = kMinAmplitude;

  MicRecorderDelegate({required this.onStateChanged});

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
    if (context != null && context.state == 'suspended') {
      await context.resume().toDart;

      if (_workletNode != null) {
        // Workaround for Chromium based browsers,
        // Audio worklet node is disconnected
        // when pause state is too long (> 12~15 secs)
        _source?.connect(_workletNode!)?.connect(context.destination);
      }

      onStateChanged(RecordState.record);
    }
  }

  @override
  Future<void> start(RecordConfig config, {required String path}) {
    return _start(config);
  }

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    await _recordStreamCtrl?.close();
    final streamController = StreamController<Uint8List>();

    try {
      await _start(config, isStream: true);
    } catch (err) {
      debugPrint(err.toString());
      await streamController.close();
      rethrow;
    }

    _recordStreamCtrl = streamController;

    return streamController.stream;
  }

  @override
  Future<String?> stop() async {
    await _reset(resetEncoder: false);

    final blob = _encoder?.finish();
    _encoder?.cleanup();
    _encoder = null;

    onStateChanged(RecordState.stop);

    return blob != null ? web.URL.createObjectURL(blob) : null;
  }

  Future<void> _start(RecordConfig config, {bool isStream = false}) async {
    final mediaStream = await initMediaStream(config);
    _mediaStream = mediaStream;

    // TODO: Remove Firefox detection to better handle sample rate support with
    // track constraints (failed to convert ConstaintULong for now).
    final isFirefox =
        web.window.navigator.userAgent.toLowerCase().contains('firefox');
    final context = switch (isFirefox) {
      true => web.AudioContext(),
      false => web.AudioContext(
          web.AudioContextOptions(sampleRate: config.sampleRate.toDouble()),
        ),
    };

    final source = context.createMediaStreamSource(mediaStream);

    // TODO Remove record.worklet.js from assets and use it from lib sources.
    // This will avoid to propagate it on non web platforms.
    await context.audioWorklet
        .addModule('assets/packages/record_web/assets/js/record.worklet.js')
        .toDart;

    final workletNode = web.AudioWorkletNode(
      context,
      'recorder.worklet',
      web.AudioWorkletNodeOptions(
        parameterData: {
          'numChannels'.toJS: config.numChannels.toJS,
          'sampleRate'.toJS: config.sampleRate.toJS,
        }.jsify()! as JSObject,
      ),
    );

    source.connect(workletNode)?.connect(context.destination);

    if (!isStream) {
      _encoder?.cleanup();

      if (config.encoder == AudioEncoder.wav) {
        _encoder = WavEncoder(
          sampleRate: config.sampleRate,
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
      workletNode.port.onmessage =
          ((web.MessageEvent event) => _onMessage(event)).toJS;
    }

    _source = source;
    _workletNode = workletNode;
    _context = context;
    _mediaStream = mediaStream;

    onStateChanged(RecordState.record);
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
      _recordStreamCtrl?.add(output.buffer.asUint8List());
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
    await resetContext(_context, _mediaStream);
    _mediaStream = null;
    _context = null;

    if (resetEncoder) {
      _encoder?.cleanup();
      _encoder = null;
    }

    _maxAmplitude = kMinAmplitude;
    _amplitude = kMinAmplitude;

    _recordStreamCtrl?.close();
    _recordStreamCtrl = null;
  }
}
