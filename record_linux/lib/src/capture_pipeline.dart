import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:record_platform_interface/record_platform_interface.dart';

import 'amplitude_tracker.dart';
import 'process_args.dart';

/// Which program captures the microphone.
enum LinuxCaptureBackend {
  /// parecord, from pulseaudio-utils. Follows the PulseAudio/PipeWire
  /// default source and exposes every source through `pactl`.
  pulseAudio,

  /// ffmpeg reading ALSA directly, for machines with no PulseAudio or
  /// PipeWire server, and for apps that ship their own ffmpeg.
  ffmpegAlsa,
}

/// Captures with parecord or ffmpeg, and encodes with ffmpeg when
/// recording to a file.
///
/// capture -> amplitude -> ffmpeg (encode) -> file
class CapturePipeline {
  CapturePipeline({
    this.parecordBin = 'parecord',
    this.ffmpegBin = 'ffmpeg',
    this.backend,
    this.alsaDevice = 'default',
  });

  final String parecordBin;
  final String ffmpegBin;

  /// Null asks for the backend to be detected once, preferring
  /// [LinuxCaptureBackend.pulseAudio] when parecord can be run.
  final LinuxCaptureBackend? backend;

  /// The ALSA device recorded from when the config names none.
  final String alsaDevice;

  LinuxCaptureBackend? _resolvedBackend;

  final amplitude = AmplitudeTracker();

  Process? _capture;
  Process? _ffmpeg;
  StreamController<List<int>>? _inputPcm;
  Future<void>? _pipeDone;

  /// Captures to [path], encoded by ffmpeg.
  Future<void> startFile(RecordConfig config, String path) async {
    await _startCapture(config);

    final args = [
      '-f',
      's16le',
      '-ar',
      config.sampleRate.toString(),
      '-ac',
      '${config.numChannels}',
      '-i',
      '-',
      ...ffmpegEncoderArgs(config.encoder, path, config.bitRate),
    ];

    _ffmpeg = await Process.start(ffmpegBin, args);
    // ffmpeg reports progress on stderr until it exits; a full pipe would
    // block it in write() and stall the recording.
    _drain(_ffmpeg!.stdout);
    _drain(_ffmpeg!.stderr);

    _inputPcm = StreamController<List<int>>();

    _capture!.stdout.listen((data) {
      final typed = data is Uint8List ? data : Uint8List.fromList(data);
      amplitude.update(typed);

      if (_inputPcm case final ctrl? when !ctrl.isClosed) ctrl.add(typed);
    }, onDone: () => _inputPcm?.close());

    // pipe() gives backpressure and closes ffmpeg stdin at the end.
    _pipeDone = _inputPcm!.stream.pipe(_ffmpeg!.stdin);
  }

  /// Captures to the returned PCM stream, without ffmpeg.
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    await _startCapture(config);

    return _capture!.stdout.map((list) {
      final data = list is Uint8List ? list : Uint8List.fromList(list);
      amplitude.update(data);
      return data;
    });
  }

  void pause() => _capture?.kill(ProcessSignal.sigstop);

  void resume() => _capture?.kill(ProcessSignal.sigcont);

  Future<void> stop() async {
    await _inputPcm?.close();
    _inputPcm = null;

    // Kill the source first so the input pipe reaches its end.
    _capture?.kill();
    _capture = null;

    if (_ffmpeg case final process?) {
      try {
        await _pipeDone;
      } catch (_) {
        // ffmpeg may have exited early on a broken pipe.
      }
      _pipeDone = null;
      await process.exitCode;
      _ffmpeg = null;
    }

    amplitude.reset();
  }

  Future<void> _startCapture(RecordConfig config) async {
    _capture = switch (_backend()) {
      LinuxCaptureBackend.pulseAudio => await Process.start(
        parecordBin,
        parecordArgs(config),
      ),
      LinuxCaptureBackend.ffmpegAlsa => await Process.start(
        ffmpegBin,
        ffmpegAlsaCaptureArgs(config, defaultDevice: alsaDevice),
      ),
    };

    _drain(_capture!.stderr);
  }

  /// The configured backend, or parecord when it is installed and ffmpeg
  /// otherwise. Detected once: every later recording reuses the answer.
  LinuxCaptureBackend _backend() {
    if (backend case final configured?) return configured;

    if (_resolvedBackend case final resolved?) return resolved;

    return _resolvedBackend = _hasParecord()
        ? LinuxCaptureBackend.pulseAudio
        : LinuxCaptureBackend.ffmpegAlsa;
  }

  /// Looks the binary up rather than running it: a capture program
  /// started to ask its version would record, print, or block, depending
  /// on the program.
  bool _hasParecord() {
    if (parecordBin.contains('/')) return File(parecordBin).existsSync();

    for (final directory in (Platform.environment['PATH'] ?? '').split(':')) {
      if (directory.isEmpty) continue;

      if (File('$directory/$parecordBin').existsSync()) return true;
    }

    return false;
  }

  /// Discards a process output pipe, which would otherwise fill and block it.
  void _drain(Stream<List<int>> output) {
    output.listen((_) {}, onError: (_) {}, cancelOnError: true);
  }
}
