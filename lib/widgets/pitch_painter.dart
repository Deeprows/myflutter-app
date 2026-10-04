import 'package:flutter/material.dart';

/// Faint football-pitch line art used as a header backdrop.
class PitchPainter extends CustomPainter {
  final Color color;
  const PitchPainter({this.color = const Color(0x0DFFFFFF)});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final r = Rect.fromLTWH(14, 14, size.width - 28, size.height - 28);
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(10)), p);
    canvas.drawLine(
        Offset(size.width / 2, r.top), Offset(size.width / 2, r.bottom), p);
    canvas.drawCircle(
        Offset(size.width / 2, size.height / 2), size.height * .30, p);
    final box = size.height * .34;
    canvas.drawRect(
        Rect.fromLTWH(r.left, size.height / 2 - box / 2, box * .7, box), p);
    canvas.drawRect(
        Rect.fromLTWH(r.right - box * .7, size.height / 2 - box / 2, box * .7, box),
        p);
  }

  @override
  bool shouldRepaint(covariant PitchPainter old) => old.color != color;
}
