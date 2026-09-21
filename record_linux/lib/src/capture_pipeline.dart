import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:record_platform_interface/record_platform_interface.dart';

import 'amplitude_tracker.dart';
import 'process_args.dart';

/// Captures with parecord, and encodes with ffmpeg when recording to a file.
///
/// parecord (capture) -> amplitude -> ffmpeg (encode) -> file
class CapturePipeline {
  CapturePipeline({this.parecordBin = 'parecord', this.ffmpegBin = 'ffmpeg'});

  final String parecordBin;
  final String ffmpegBin;

  final amplitude = AmplitudeTracker();

  Process? _parecord;
  Process? _ffmpeg;
  StreamController<List<int>>? _inputPcm;
  Future<void>? _pipeDone;

  /// Captures to [path], encoded by ffmpeg.
  Future<void> startFile(RecordConfig config, String path) async {
    await _startParecord(config);

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

    _parecord!.stdout.listen((data) {
      final typed = data is Uint8List ? data : Uint8List.fromList(data);
      amplitude.update(typed);

      if (_inputPcm case final ctrl? when !ctrl.isClosed) ctrl.add(typed);
    }, onDone: () => _inputPcm?.close());

    // pipe() gives backpressure and closes ffmpeg stdin at the end.
    _pipeDone = _inputPcm!.stream.pipe(_ffmpeg!.stdin);
  }

  /// Captures to the returned PCM stream, without ffmpeg.
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    await _startParecord(config);

    return _parecord!.stdout.map((list) {
      final data = list is Uint8List ? list : Uint8List.fromList(list);
      amplitude.update(data);
      return data;
    });
  }

  void pause() => _parecord?.kill(ProcessSignal.sigstop);

  void resume() => _parecord?.kill(ProcessSignal.sigcont);

  Future<void> stop() async {
    await _inputPcm?.close();
    _inputPcm = null;

    // Kill the source first so the input pipe reaches its end.
    _parecord?.kill();
    _parecord = null;

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

  Future<void> _startParecord(RecordConfig config) async {
    _parecord = await Process.start(parecordBin, parecordArgs(config));
    _drain(_parecord!.stderr);
  }

  /// Discards a process output pipe, which would otherwise fill and block it.
  void _drain(Stream<List<int>> output) {
    output.listen((_) {}, onError: (_) {}, cancelOnError: true);
  }
}
