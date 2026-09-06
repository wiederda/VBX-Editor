import 'package:flutter/material.dart';

class DryRunIcon extends StatelessWidget {
  final Color? color;
  final double size;

  const DryRunIcon({super.key, this.color, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _DryRunIconPainter(
        color: color ?? IconTheme.of(context).color ?? Colors.black,
      ),
    );
  }
}

class _DryRunIconPainter extends CustomPainter {
  final Color color;

  _DryRunIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Lupenkreis, nach oben-links versetzt, damit unten rechts
    // Platz für den Griff bleibt.
    final lensCenter = Offset(size.width * 0.42, size.height * 0.42);
    final lensRadius = size.width * 0.28;

    canvas.drawCircle(lensCenter, lensRadius, paint);

    // Griff der Lupe, diagonal nach unten rechts
    final handleStart = Offset(
      lensCenter.dx + lensRadius * 0.75,
      lensCenter.dy + lensRadius * 0.75,
    );
    final handleEnd = Offset(size.width * 0.88, size.height * 0.88);

    canvas.drawLine(handleStart, handleEnd, paint);

    // Häkchen innerhalb des Lupenkreises
    final checkPaint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(lensCenter.dx - lensRadius * 0.45, lensCenter.dy)
      ..lineTo(
        lensCenter.dx - lensRadius * 0.1,
        lensCenter.dy + lensRadius * 0.35,
      )
      ..lineTo(
        lensCenter.dx + lensRadius * 0.5,
        lensCenter.dy - lensRadius * 0.35,
      );

    canvas.drawPath(path, checkPaint);
  }

  @override
  bool shouldRepaint(covariant _DryRunIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
