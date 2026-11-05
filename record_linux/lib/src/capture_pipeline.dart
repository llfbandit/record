import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:record_platform_interface/record_platform_interface.dart';

import 'amplitude_tracker.dart';
import 'output_tail.dart';
import 'process_args.dart';

/// Captures with parecord, and encodes with ffmpeg when recording to a file.
///
/// parecord (capture) -> amplitude -> ffmpeg (encode) -> file
class CapturePipeline {
  CapturePipeline({this.parecordBin = 'parecord', this.ffmpegBin = 'ffmpeg'});

  final String parecordBin;
  final String ffmpegBin;

  final amplitude = AmplitudeTracker();

  /// Called when parecord ([capture]) or ffmpeg exits before [stop] ends it.
  void Function(String error, {required bool capture})? onExited;

  Process? _parecord;
  StreamSubscription<List<int>>? _capture;
  Process? _ffmpeg;
  StreamController<Uint8List>? _pcm;
  Future<void>? _pipeDone;

  /// The parecord process, whose stream a route monitor watches.
  int? get capturePid => _parecord?.pid;

  /// Captures to [path], encoded by ffmpeg.
  Future<void> startFile(RecordConfig config, String path) async {
    final pcm = _openPcm();
    await _startParecord(config);

    final args = [
      // Progress and stats would push the error out of the stderr tail.
      '-loglevel',
      'error',
      '-nostats',
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

    final ffmpeg = _ffmpeg = await Process.start(ffmpegBin, args);
    // A full pipe would block ffmpeg in write() and stall the recording.
    _drain(ffmpeg.stdout);
    final tail = OutputTail(ffmpeg.stderr);

    unawaited(
      ffmpeg.exitCode.then((code) async {
        final reason = await tail.text();
        // stop() drops the PCM stream before ffmpeg ends.
        if (identical(ffmpeg, _ffmpeg) && _pcm != null) {
          onExited?.call(_exitError('ffmpeg', code, reason), capture: false);
        }
      }),
    );

    // addStream() gives backpressure; pipe() would reject the Uint8List
    // stream for ffmpeg's List<int> sink at runtime.
    final stdin = ffmpeg.stdin;
    _pipeDone = stdin.addStream(pcm.stream).then((_) => stdin.close());
  }

  /// Captures to the returned PCM stream, without ffmpeg.
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    final pcm = _openPcm();
    await _startParecord(config);

    return pcm.stream;
  }

  /// Captures from [config]'s device into the same file or stream.
  Future<void> restartCapture(RecordConfig config) async {
    suspendCapture();
    await _startParecord(config);
  }

  /// Ends capture but keeps the file or stream open for [restartCapture].
  void suspendCapture() {
    _capture?.cancel();
    _capture = null;

    if (_parecord case final process?) _kill(process);
    _parecord = null;
  }

  void pause() => _parecord?.kill(ProcessSignal.sigstop);

  void resume() => _parecord?.kill(ProcessSignal.sigcont);

  Future<void> stop() async {
    // End the source first so the input pipe reaches its end.
    suspendCapture();

    // Not awaited: close() waits for a listener a stream take may not have.
    unawaited(_pcm?.close());
    _pcm = null;

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

  // Outlives parecord, so a route change can swap the source mid-take.
  StreamController<Uint8List> _openPcm() {
    return _pcm = StreamController<Uint8List>(
      onPause: () => _capture?.pause(),
      onResume: () => _capture?.resume(),
    );
  }

  Future<void> _startParecord(RecordConfig config) async {
    final pcm = _pcm;
    final process = await Process.start(parecordBin, parecordArgs(config));

    // The take may end while parecord starts.
    if (pcm == null || !identical(pcm, _pcm)) {
      _drain(process.stdout);
      _drain(process.stderr);
      return _kill(process);
    }

    // Two overlapping restarts would otherwise leave one parecord behind.
    suspendCapture();
    _parecord = process;
    final tail = OutputTail(process.stderr);

    _capture = process.stdout.listen((data) {
      final typed = data is Uint8List ? data : Uint8List.fromList(data);
      amplitude.update(typed);

      if (_pcm case final pcm? when !pcm.isClosed) pcm.add(typed);
    }, onError: (_) {});
    // onPause fired for the previous parecord: keep the backpressure. Without
    // a listener yet, isPaused is true too, and onListen would not resume.
    if (pcm.hasListener && pcm.isPaused) _capture!.pause();

    unawaited(
      process.exitCode.then((code) async {
        final reason = await tail.text();
        // suspendCapture() drops the process before killing it.
        if (identical(process, _parecord)) {
          onExited?.call(_exitError('parecord', code, reason), capture: true);
        }
      }),
    );
  }

  String _exitError(String program, int code, String reason) {
    return reason.isEmpty
        ? '$program exited ($code).'
        : '$program exited ($code): $reason';
  }

  /// A paused parecord holds SIGTERM until it continues.
  void _kill(Process process) {
    process.kill();
    process.kill(ProcessSignal.sigcont);
  }

  /// Discards a process output pipe, which would otherwise fill and block it.
  void _drain(Stream<List<int>> output) {
    output.listen((_) {}, onError: (_) {}, cancelOnError: true);
  }
}
