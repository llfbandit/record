import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/material.dart';

class AudioPlayer extends StatefulWidget {
  /// Path from where to play recorded audio
  final String path;

  /// Callback when audio file should be removed
  /// Setting this to null hides the delete button
  final VoidCallback onDelete;

  const AudioPlayer({
    Key key,
    @required this.path,
    this.onDelete,
  }) : super(key: key);

  @override
  AudioPlayerState createState() => AudioPlayerState();
}

class AudioPlayerState extends State<AudioPlayer> {
  static const double _controlSize = 56;
  static const double _deleteBtnSize = 24;

  final _audioPlayer = ap.AudioPlayer();
  ap.AudioPlayerState _status;
  Duration _duration;
  Duration _position;

  @override
  void initState() {
    _status = ap.AudioPlayerState.STOPPED;

    _audioPlayer.onPlayerStateChanged.listen(_onPlayerStateChanged);
    _audioPlayer.onDurationChanged.listen(_onDurationChanged);
    _audioPlayer.onAudioPositionChanged.listen(_onAudioPositionChanged);
    _audioPlayer.onPlayerError.listen((error) => print(error));

    super.initState();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            _buildControl(),
            _buildSlider(constraints.maxWidth),
            if (widget.onDelete != null)
              IconButton(
                icon: Icon(Icons.delete,
                    color: const Color(0xFF73748D), size: _deleteBtnSize),
                onPressed: () => widget.onDelete(),
              ),
          ],
        );
      },
    );
  }

  Widget _buildControl() {
    Icon icon;
    Color color;

    if (_status == ap.AudioPlayerState.PLAYING) {
      icon = Icon(Icons.stop, color: Colors.red, size: 30);
      color = Colors.red.withOpacity(0.1);
    } else {
      final theme = Theme.of(context);
      icon = Icon(Icons.play_arrow, color: theme.primaryColor, size: 30);
      color = theme.primaryColor.withOpacity(0.1);
    }

    return ClipOval(
      child: Material(
        color: color,
        child: InkWell(
          child:
              SizedBox(width: _controlSize, height: _controlSize, child: icon),
          onTap: () {
            if (_status == ap.AudioPlayerState.PLAYING) {
              pause();
            } else if (_status == ap.AudioPlayerState.PAUSED) {
              resume();
            } else {
              play();
            }
          },
        ),
      ),
    );
  }

  Widget _buildSlider(double widgetWidth) {
    bool canSetValue = false;
    if (_position != null && _duration != null) {
      canSetValue = _position.inMilliseconds > 0;
      canSetValue &= _position.inMilliseconds < _duration.inMilliseconds;
    }

    double width = widgetWidth - _controlSize - _deleteBtnSize;
    if (widget.onDelete != null) {
      width -= _deleteBtnSize;
    }

    return SizedBox(
      width: width,
      child: Slider(
        activeColor: Theme.of(context).primaryColor,
        inactiveColor: Theme.of(context).accentColor,
        onChanged: (v) {
          if (_position != null) {
            final position = v * _position.inMilliseconds;
            _audioPlayer.seek(Duration(milliseconds: position.round()));
          }
        },
        value: canSetValue
            ? _position.inMilliseconds / _duration.inMilliseconds
            : 0.0,
      ),
    );
  }

  Future<int> play() {
    return _audioPlayer.play(widget.path, isLocal: true);
  }

  Future<int> resume() {
    return _audioPlayer.resume();
  }

  Future<int> pause() {
    return _audioPlayer.pause();
  }

  void _onPlayerStateChanged(ap.AudioPlayerState status) {
    setState(() => _status = status);
  }

  void _onDurationChanged(Duration duration) {
    setState(() => _duration = duration);
  }

  void _onAudioPositionChanged(Duration position) {
    setState(() => _position = position);
  }
}
