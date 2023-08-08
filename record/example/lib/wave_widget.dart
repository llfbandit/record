import 'dart:math';

import 'package:flutter/material.dart';

class WavePainter extends CustomPainter {
  final double frequency;
  final int density;
  final double phase;
  final double normedAmplitude;
  final Color color;

  WavePainter({
    required this.frequency,
    required this.density,
    required this.phase,
    required this.normedAmplitude,
    required this.color,
  }) : super();

  @override
  void paint(Canvas canvas, Size size) {
    var path = Path();
    var maxAmplitude = size.height / 2.0;
    var mid = size.width / 2;

    for (var x = 0; x < size.width + density; x += density) {
      // Parabolic scaling
      var scaling = -pow(1 / mid * (x - mid), 2) + 1;
      var y = scaling *
          maxAmplitude *
          normedAmplitude *
          sin(pi * 2 * frequency * (x / size.width) + phase);
      if (x == 0) {
        path.moveTo(x.toDouble(), y);
      } else {
        path.lineTo(x.toDouble(), y);
      }
    }

    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(WavePainter oldDelegate) {
    return oldDelegate.frequency != frequency ||
        oldDelegate.density != density ||
        oldDelegate.phase != phase ||
        oldDelegate.normedAmplitude != normedAmplitude;
  }
}

class WaveWidget extends StatelessWidget {
  final double amplitude;
  final Color color;
  final double phase;

  const WaveWidget({
    Key? key,
    required this.amplitude,
    required this.color,
    required this.phase,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    return SizedBox(
      width: sw,
      height: 200,
      child: CustomPaint(
        painter: WavePainter(
          phase: phase,
          normedAmplitude: amplitude * (1.5 - 0.8),
          color: color,
          frequency: 1.5,
          density: 1,
        ),
      ),
    );
  }
}
