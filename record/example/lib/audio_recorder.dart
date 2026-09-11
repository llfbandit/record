import 'dart:async';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import 'platform/audio_recorder_platform.dart';

class Recorder extends StatefulWidget {
  final void Function(String path) onStop;

  const Recorder({super.key, required this.onStop});

  @override
  State<Recorder> createState() => _RecorderState();
}

class _RecorderState extends State<Recorder> with AudioRecorderMixin {
  int _recordDuration = 0;
  Timer? _timer;
  late final AudioRecorder _audioRecorder;
  StreamSubscription<RecordState>? _recordSub;
  RecordState _recordState = RecordState.stop;
  StreamSubscription<Amplitude>? _amplitudeSub;
  Amplitude? _amplitude;

  RecordConfig _config = const RecordConfig(numChannels: 1);
  bool _useStream = false;
  List<InputDevice> _inputDevices = [];

  String? _statusBarContent;

  @override
  void initState() {
    _audioRecorder = AudioRecorder();

    _recordSub = _audioRecorder.onStateChanged().listen(
      (recordState) => _updateRecordState(recordState),
    );

    _amplitudeSub = _audioRecorder
        .onAmplitudeChanged(const Duration(milliseconds: 300))
        .listen((amp) => setState(() => _amplitude = amp));

    _loadInputDevices();

    super.initState();
  }

  Future<void> _loadInputDevices() async {
    final devices = await _audioRecorder.listInputDevices();
    setState(() => _inputDevices = devices);
  }

  Future<void> _start() async {
    setState(() => _statusBarContent = null);

    try {
      if (await _audioRecorder.hasPermission()) {
        if (!await _isEncoderSupported(_config.encoder)) {
          return;
        }

        _audioRecorder.setOnConfigChanged((config) {
          setState(() => _statusBarContent = config.toString());
        });

        if (_useStream) {
          await recordStream(_audioRecorder, _config, onStop: widget.onStop);
        } else {
          await recordFile(_audioRecorder, _config);
        }
      }
    } catch (e) {
      setState(() => _statusBarContent = e.toString());
    }
  }

  Future<void> _stop() async {
    final path = await _audioRecorder.stop();

    if (path != null) {
      widget.onStop(path);

      downloadWebData(path, _config.encoder);
    }
  }

  Future<void> _pause() => _audioRecorder.pause();

  Future<void> _resume() => _audioRecorder.resume();

  void _updateRecordState(RecordState recordState) {
    setState(() => _recordState = recordState);

    switch (recordState) {
      case RecordState.pause:
        _timer?.cancel();
      case RecordState.record:
        _startTimer();
      case RecordState.stop:
        _timer?.cancel();
        _recordDuration = 0;
        _amplitude = null;
    }
  }

  Future<bool> _isEncoderSupported(AudioEncoder encoder) async {
    final isSupported = await _audioRecorder.isEncoderSupported(encoder);

    if (!isSupported) {
      final supported = <String>[];
      for (final e in AudioEncoder.values) {
        if (await _audioRecorder.isEncoderSupported(e)) {
          supported.add(e.name);
        }
      }
      setState(() {
        _statusBarContent =
            '${encoder.name} is not supported. Supported: ${supported.join(', ')}.';
      });
    }

    return isSupported;
  }

  @override
  Widget build(BuildContext context) {
    final isStopped = _recordState == RecordState.stop;

    return SafeArea(
      child: Stack(
        children: [
          if (isStopped)
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: _RecordConfigControls(
                        config: _config,
                        onConfigChanged: (v) => setState(() => _config = v),
                        useStream: _useStream,
                        onUseStreamChanged: (v) =>
                            setState(() => _useStream = v),
                        inputDevices: _inputDevices,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _StatusBar(info: _statusBarContent),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 40,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 20,
                  children: <Widget>[
                    _RecordStopControl(
                      _recordState,
                      onStart: _start,
                      onStop: _stop,
                    ),
                    _PauseResumeControl(
                      _recordState,
                      onPause: _pause,
                      onResume: _resume,
                    ),
                    _Timer(_recordState, _recordDuration),
                  ],
                ),
                if (_amplitude != null)
                  Column(
                    children: [
                      Text('Current: ${_amplitude?.current ?? 0.0}'),
                      Text('Max: ${_amplitude?.max ?? 0.0}'),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recordSub?.cancel();
    _amplitudeSub?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      setState(() => _recordDuration++);
    });
  }
}

class _Timer extends StatelessWidget {
  final RecordState _recordState;
  final int _recordDuration;

  const _Timer(this._recordState, this._recordDuration);

  @override
  Widget build(BuildContext context) {
    if (_recordState != RecordState.stop) {
      return _buildTimer();
    }

    return const Text("Waiting for recording");
  }

  Widget _buildTimer() {
    String formatNumber(int number) {
      return '$number'.padLeft(2, '0');
    }

    final String minutes = formatNumber(_recordDuration ~/ 60);
    final String seconds = formatNumber(_recordDuration % 60);

    return Text(
      '$minutes : $seconds',
      style: const TextStyle(color: Colors.red),
    );
  }
}

class _RecordStopControl extends StatelessWidget {
  final RecordState _recordState;
  final VoidCallback onStop;
  final VoidCallback onStart;

  const _RecordStopControl(
    this._recordState, {
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    late Icon icon;
    late Color color;

    if (_recordState != RecordState.stop) {
      icon = const Icon(Icons.stop, color: Colors.red, size: 30);
      color = Colors.red.withValues(alpha: 0.1);
    } else {
      final theme = Theme.of(context);
      icon = Icon(Icons.mic, color: theme.primaryColor, size: 30);
      color = theme.primaryColor.withValues(alpha: 0.1);
    }

    return ClipOval(
      child: Material(
        color: color,
        child: InkWell(
          child: SizedBox(width: 56, height: 56, child: icon),
          onTap: () {
            (_recordState != RecordState.stop) ? onStop() : onStart();
          },
        ),
      ),
    );
  }
}

class _PauseResumeControl extends StatelessWidget {
  final RecordState _recordState;
  final VoidCallback onResume;
  final VoidCallback onPause;

  const _PauseResumeControl(
    this._recordState, {
    required this.onPause,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    if (_recordState == RecordState.stop) {
      return const SizedBox.shrink();
    }

    late Icon icon;
    late Color color;

    if (_recordState == RecordState.record) {
      icon = const Icon(Icons.pause, color: Colors.red, size: 30);
      color = Colors.red.withValues(alpha: 0.1);
    } else {
      final theme = Theme.of(context);
      icon = const Icon(Icons.play_arrow, color: Colors.red, size: 30);
      color = theme.primaryColor.withValues(alpha: 0.1);
    }

    return ClipOval(
      child: Material(
        color: color,
        child: InkWell(
          child: SizedBox(width: 56, height: 56, child: icon),
          onTap: () {
            (_recordState == RecordState.pause) ? onResume() : onPause();
          },
        ),
      ),
    );
  }
}

class _RecordConfigControls extends StatelessWidget {
  final RecordConfig config;
  final ValueChanged<RecordConfig> onConfigChanged;
  final bool useStream;
  final ValueChanged<bool> onUseStreamChanged;
  final List<InputDevice> inputDevices;

  static const _sampleRates = [2, 8000, 16000, 22050, 44100, 48000, 96000];

  const _RecordConfigControls({
    required this.config,
    required this.onConfigChanged,
    required this.useStream,
    required this.onUseStreamChanged,
    required this.inputDevices,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodyMedium;

    Widget row(String label, Widget control, {bool expand = false}) {
      return Row(
        children: [
          Expanded(child: Text(label, style: labelStyle)),
          if (expand) Expanded(flex: 2, child: control) else control,
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row(
          'Stream',
          Checkbox(value: useStream, onChanged: (v) => onUseStreamChanged(v!)),
        ),
        if (inputDevices.isNotEmpty)
          row(
            'Device',
            DropdownButton<InputDevice?>(
              value: config.device,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: [
                const DropdownMenuItem(value: null, child: Text('Default')),
                ...inputDevices.map(
                  (d) => DropdownMenuItem(
                    value: d,
                    child: Text(d.label, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (v) =>
                  onConfigChanged(config.copyWith(device: (value: v))),
            ),
            expand: true,
          ),
        row(
          'Encoder',
          DropdownButton<AudioEncoder>(
            value: config.encoder,
            underline: const SizedBox.shrink(),
            items: AudioEncoder.values
                .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                .toList(),
            onChanged: (v) => onConfigChanged(config.copyWith(encoder: v!)),
          ),
        ),
        row(
          'Channels',
          DropdownButton<int>(
            value: config.numChannels,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 1, child: Text('Mono')),
              DropdownMenuItem(value: 2, child: Text('Stereo')),
              DropdownMenuItem(value: 9, child: Text('!! 9 !!')),
            ],
            onChanged: (v) => onConfigChanged(config.copyWith(numChannels: v!)),
          ),
        ),
        row(
          'Sample rate',
          DropdownButton<int>(
            value: config.sampleRate,
            underline: const SizedBox.shrink(),
            items: _sampleRates
                .map((r) => DropdownMenuItem(value: r, child: Text('$r Hz')))
                .toList(),
            onChanged: (v) => onConfigChanged(config.copyWith(sampleRate: v!)),
          ),
        ),
      ],
    );
  }
}

class _StatusBar extends StatelessWidget {
  final String? info;

  const _StatusBar({this.info});

  @override
  Widget build(BuildContext context) {
    if (info == null) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        info!,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
