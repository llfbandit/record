import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import 'amplitude_tracker.dart';
import 'output_tail.dart';
import 'process_args.dart';
import 'process_state.dart';

/// How long a capture gets to end before it is killed.
const captureStopTimeout = Duration(milliseconds: 2000);

/// The same, while a new take waits for the old capture to let go.
const captureRestartStopTimeout = Duration(milliseconds: 500);

/// Captures with parecord, and encodes with ffmpeg when recording to a file.
///
/// parecord (capture) -> amplitude -> ffmpeg (encode) -> file
class CapturePipeline {
  CapturePipeline({
    this.parecordBin = 'parecord',
    this.ffmpegBin = 'ffmpeg',
    this.stopTimeout = captureStopTimeout,
    this.restartStopTimeout = captureRestartStopTimeout,
  });

  final String parecordBin;
  final String ffmpegBin;

  /// How long stop() gives the capture before it kills it.
  ///
  /// Internal for now, to be configurable through `RecordLinuxOptions`:
  /// https://github.com/llfbandit/record/issues/640
  final Duration stopTimeout;

  /// The same for a capture a new take waits on, which is shorter because
  /// nothing can be recorded until the old capture is gone.
  ///
  /// Internal for now, to be configurable through `RecordLinuxOptions`:
  /// https://github.com/llfbandit/record/issues/640
  final Duration restartStopTimeout;

  final amplitude = AmplitudeTracker();

  /// Called when parecord ([capture]) or ffmpeg exits before [stop] ends it.
  void Function(String error, {required bool capture})? onExited;

  Process? _parecord;
  StreamSubscription<List<int>>? _capture;
  Process? _ffmpeg;
  StreamController<Uint8List>? _pcm;
  Future<void>? _pipeDone;
  final _ending = <_CaptureEnd>[];
  final _starting = <Future<void>>[];

  /// One clock for every end of this pipeline, so their deadlines can be
  /// compared and handed on.
  final _clock = Stopwatch()..start();

  /// The deadline in force for the take that is ending, so a capture that is
  /// still starting is held to it as well.
  _Deadline? _deadline;

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

    if (_parecord case final process?) _endCapture(process);
    _parecord = null;
  }

  /// Shortens the wait for the captures that are still ending.
  ///
  /// A take that is starting calls it, because it cannot record until the
  /// capture before it has let go of the device.
  void hurryEnds() => _endsBy(
    _Deadline(
      _clock.elapsed + restartStopTimeout,
      _Ending.restart,
      restartStopTimeout,
    ),
  );

  /// Puts [deadline] in force, for the captures that are ending and for any
  /// that is still starting - unless a sooner one already is.
  void _endsBy(_Deadline deadline) {
    if (_deadline case final current?
        when !comesSooner(deadline.due, current.due)) {
      return;
    }

    _deadline = deadline;
    for (final end in _ending) {
      end.killAt(deadline);
    }
  }

  void pause() => _parecord?.kill(ProcessSignal.sigstop);

  void resume() => _parecord?.kill(ProcessSignal.sigcont);

  /// Ends the take, and returns once every capture of it is gone.
  ///
  /// A take that is starting passes [restarting], which gives the captures
  /// that are ending the shorter [restartStopTimeout].
  Future<void> stop({bool restarting = false}) async {
    final timeout = restarting ? restartStopTimeout : stopTimeout;
    final ending = restarting ? _Ending.restart : _Ending.stop;
    _endsBy(_Deadline(_clock.elapsed + timeout, ending, timeout));

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

    // A capture that is still starting is settled first: it may yet have to
    // be ended, and then it belongs to this stop too.
    for (final starting in [..._starting]) {
      try {
        await starting;
      } catch (_) {
        // A start that failed leaves nothing to end.
      }
    }

    // Last, so the capture ends while the encoder finishes rather than after.
    await Future.wait([for (final end in _ending) end.gone]);

    _deadline = null;
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
    final starting = _startCapture(config);

    // Kept while it runs, so a stop can wait for a capture that is still
    // starting: it may have to be ended after the stop read the ends.
    _starting.add(starting);
    try {
      await starting;
    } finally {
      _starting.remove(starting);
    }
  }

  Future<void> _startCapture(RecordConfig config) async {
    final pcm = _pcm;
    final process = await Process.start(parecordBin, parecordArgs(config));

    // The take may end while parecord starts.
    if (pcm == null || !identical(pcm, _pcm)) {
      _drain(process.stdout);
      _drain(process.stderr);
      return _endCapture(process);
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

  /// Ends [process] and keeps the wait for it, so [stop] can join it.
  ///
  /// The wait runs on its own, so a route change does not have to sit it out
  /// while the capture it replaced is still going.
  void _endCapture(Process process) {
    final end = _CaptureEnd(process, _clock);
    // A capture that starts while the take is ending is held to the deadline
    // that end asked for, however late it turns up.
    final deadline =
        _deadline ??
        _Deadline(_clock.elapsed + stopTimeout, _Ending.stop, stopTimeout);

    _ending.add(end);
    end.killAt(deadline);
    unawaited(end.gone.then((_) => _ending.remove(end)));
  }

  /// Discards a process output pipe, which would otherwise fill and block it.
  void _drain(Stream<List<int>> output) {
    output.listen((_) {}, onError: (_) {}, cancelOnError: true);
  }
}

/// Whether the deadline [due] replaces the [current] one.
///
/// Only a sooner one does, so asking for more time can never push a kill
/// that is already due further away. Both are elapsed times of the
/// pipeline's clock, so a wall clock that jumps cannot lengthen a deadline.
bool comesSooner(Duration due, Duration? current) =>
    current == null || due < current;

/// When a capture of a take that is ending has to be gone, and why.
///
/// [due] is an elapsed time of the pipeline's clock rather than a moment, so
/// it can be handed to a capture that only turns up later: that one inherits
/// the deadline instead of starting its own.
class _Deadline {
  const _Deadline(this.due, this.ending, this.timeout);

  final Duration due;
  final _Ending ending;

  /// What was asked for, for the log.
  final Duration timeout;
}

/// Why a capture is ending, for the log when it has to be killed.
enum _Ending {
  stop('stop()', 'stopTimeout'),
  restart('a new start()', 'restartStopTimeout');

  const _Ending(this.after, this.timeout);

  /// What asked for the end.
  final String after;

  /// The parameter the deadline came from.
  final String timeout;
}

/// One capture on its way out: SIGTERM at once, SIGKILL if it takes too long.
class _CaptureEnd {
  _CaptureEnd(this._process, this._clock) {
    _process.kill();
    // A paused parecord holds SIGTERM until it continues.
    _process.kill(ProcessSignal.sigcont);
    unawaited(_process.exitCode.then((_) => _done()));
  }

  final Process _process;
  final Stopwatch _clock;
  final _exited = Completer<void>();
  Timer? _timer;
  Duration? _due;

  /// Completes once the process is really gone.
  Future<void> get gone => _exited.future;

  /// Kills the process when [deadline] is up, unless it is already due sooner.
  ///
  /// A deadline that has passed - a capture that took longer to start than
  /// the take had left - is acted on at once.
  void killAt(_Deadline deadline) {
    if (_exited.isCompleted) return;
    if (!comesSooner(deadline.due, _due)) return;

    _due = deadline.due;
    _timer?.cancel();

    final left = deadline.due - _clock.elapsed;
    // A deadline that is already up is acted on after an exit Dart may have
    // seen in the meantime: _done() runs on the exit continuation, and
    // killing or reading /proc after that could hit a reused pid.
    if (left <= Duration.zero) {
      scheduleMicrotask(() => _kill(deadline));
      return;
    }

    _timer = Timer(left, () => _kill(deadline));
  }

  void _kill(_Deadline deadline) {
    if (_exited.isCompleted) return;

    debugPrint(
      'record_linux: parecord ${_process.pid} did not end within '
      '${deadline.timeout.inMilliseconds} ms after ${deadline.ending.after} '
      '(${describeProcess(_process.pid)}), sending SIGKILL. '
      'Timeout: ${deadline.ending.timeout}, to be configurable via '
      'RecordLinuxOptions, see https://github.com/llfbandit/record/issues/640',
    );

    _process.kill(ProcessSignal.sigkill);
  }

  void _done() {
    _timer?.cancel();
    _timer = null;
    if (!_exited.isCompleted) _exited.complete();
  }
}
