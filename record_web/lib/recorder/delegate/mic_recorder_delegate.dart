import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:js_util' as jsu;

import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:record_web/encoder/encoder.dart';
import 'package:record_web/encoder/pcm_encoder.dart';
import 'package:record_web/encoder/wav_encoder.dart';
import 'package:record_web/js/js_interop/audio_context.dart';
import 'package:record_web/js/js_interop/core.dart';
import 'package:record_web/recorder/delegate/recorder_delegate.dart';
import 'package:record_web/recorder/recorder.dart';

class MicRecorderDelegate extends RecorderDelegate {
  final OnStateChanged onStateChanged;

  AudioContext? _context;
  StreamController<Uint8List>? _streamController;
  Encoder? _encoder;
  // Amplitude
  double _maxAmplitude = kMinAmplitude;
  double _amplitude = kMinAmplitude;

  MicRecorderDelegate({required this.onStateChanged});

  @override
  Future<void> dispose() async {
    final context = _context;
    if (context != null && context.state != AudioContextState.closed) {
      await context.close();
      _context = null;
    }

    return _streamController?.close();
  }

  @override
  Future<Amplitude> getAmplitude() async {
    return Amplitude(current: _amplitude, max: _maxAmplitude);
  }

  @override
  Future<bool> isPaused() async {
    return _context?.state == AudioContextState.suspended;
  }

  @override
  Future<bool> isRecording() async {
    final context = _context;
    return context != null && context.state != AudioContextState.closed;
  }

  @override
  Future<void> pause() async {
    final context = _context;
    if (context != null && context.state == AudioContextState.running) {
      onStateChanged(RecordState.pause);
      return context.suspend();
    }
  }

  @override
  Future<void> resume() async {
    final context = _context;
    if (context != null && context.state == AudioContextState.suspended) {
      onStateChanged(RecordState.record);
      return context.resume();
    }
  }

  @override
  Future<void> start(RecordConfig config, {required String path}) {
    return _start(config);
  }

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    await _streamController?.close();
    final streamController = StreamController<Uint8List>();

    try {
      await _start(config, isStream: true);
    } catch (_) {
      streamController.close();
      rethrow;
    }

    _streamController = streamController;

    return streamController.stream;
  }

  @override
  Future<String?> stop() async {
    final context = _context;
    if (context != null && context.state != AudioContextState.closed) {
      await context.close();
    }

    onStateChanged(RecordState.stop);

    final blob = _encoder?.finish();
    _encoder = null;
    _maxAmplitude = kMinAmplitude;
    _amplitude = kMinAmplitude;

    return blob != null ? Url.createObjectURL(blob) : null;
  }

  Future<void> _start(RecordConfig config, {bool isStream = false}) async {
    final mediaDevices = window.navigator.mediaDevices;

    final constraints = MediaStreamConstraints(
      audio: config.device == null
          ? true
          : {
              'deviceId': {'exact': config.device!.id}
            },
    );

    final context = AudioContext();
    final microphone = await mediaDevices.getUserMedia(constraints);

    final source = context.createMediaStreamSource(microphone);

    await context.audioWorklet.addModule(
      '/assets/packages/record_web/assets/js/record.worklet.js',
    );

    final recorder = AudioWorkletNode(context, 'recorder.worklet');
    source.connect(recorder).connect(context.destination);

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

    recorder.port.onmessage = jsu.allowInterop(
      (event) {
        if (isStream) {
          _onMessageStream(event as MessageEvent);
        } else {
          _onMessage(event as MessageEvent);
        }
      },
    );

    _context = context;

    onStateChanged(RecordState.record);
  }

  void _onMessage(MessageEvent event) {
    // `data` is a float 32 array containing audio samples
    final output = _convertFloat32toInt16(event.data);
    _encoder?.encode(output);
    _updateAmplitude(output);
  }

  void _onMessageStream(MessageEvent event) {
    // `data` is a float 32 array containing audio samples
    final output = _convertFloat32toInt16(event.data);

    final data = ByteData.sublistView(output);
    _streamController?.add(data.buffer.asUint8List());
    _updateAmplitude(output);
  }

  Int16List _convertFloat32toInt16(Float32List data) {
    final output = Int16List(data.length);

    for (var i = 0; i < data.length; i++) {
      var sample32 = data[i].clamp(-1.0, 1.0);

      output[i] = (sample32 * 0x7fff).toInt();
    }

    return output;
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
}
