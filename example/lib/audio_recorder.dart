import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

class AudioRecorder extends StatefulWidget {
  final String path;
  final VoidCallback onStop;

  const AudioRecorder({Key key, this.path, this.onStop}) : super(key: key);

  @override
  _AudioRecorderState createState() => _AudioRecorderState();
}

class _AudioRecorderState extends State<AudioRecorder> {
  static const int maxDuration = 120;

  bool _isRecording;
  int _remainingDuration;
  Timer _timer;

  @override
  void initState() {
    _isRecording = false;
    _remainingDuration = maxDuration;
    super.initState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _buildControl(),
              SizedBox(width: 20),
              _buildText(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControl() {
    Icon icon;
    Color color;

    if (_isRecording) {
      icon = Icon(Icons.stop, color: Colors.red, size: 30);
      color = Colors.red.withOpacity(0.1);
    } else {
      final theme = Theme.of(context);
      icon = Icon(Icons.mic, color: theme.primaryColor, size: 30);
      color = theme.primaryColor.withOpacity(0.1);
    }

    return ClipOval(
      child: Material(
        color: color,
        child: InkWell(
          child: SizedBox(width: 56, height: 56, child: icon),
          onTap: () {
            if (_isRecording) {
              _stop();
            } else {
              _start();
            }
          },
        ),
      ),
    );
  }

  Widget _buildText() {
    if (_isRecording) {
      return _buildTimer();
    }

    return Text("Waiting to record");
  }

  Widget _buildTimer() {
    final String minutes = _formatNumber(_remainingDuration ~/ 60);
    final String seconds = _formatNumber(_remainingDuration % 60);

    return Text(
      '$minutes : $seconds',
      style: TextStyle(color: Colors.red),
    );
  }

  String _formatNumber(int number) {
    String numberStr = number.toString();
    if (number < 10) {
      numberStr = '0' + numberStr;
    }

    return numberStr;
  }

  Future<void> _start() async {
    try {
      if (await Permission.microphone.request().isGranted) {
        await Record.start(path: widget.path);

        bool isRecording = await Record.isRecording();
        setState(() {
          _isRecording = isRecording;
          _remainingDuration = maxDuration;
        });

        _startTimer();
      }
    } catch (e) {
      print(e);
    }
  }

  Future<void> _stop() async {
    _timer?.cancel();
    await Record.stop();

    setState(() {
      _isRecording = false;
      _remainingDuration = maxDuration;
    });

    widget.onStop();
  }

  void _startTimer() {
    const tick = const Duration(milliseconds: 500);

    _timer?.cancel();

    _timer = Timer.periodic(tick, (Timer t) async {
      if (!_isRecording) {
        t.cancel();
      } else {
        setState(() {
          _remainingDuration = maxDuration - (t.tick / 2).floor();
        });

        if (_remainingDuration <= 0) {
          _stop();
        }
      }
    });
  }
}
