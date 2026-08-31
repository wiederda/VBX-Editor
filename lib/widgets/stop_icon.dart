import 'package:flutter/material.dart';

class StopIcon extends StatelessWidget {
  final Color? color;
  final double size;

  const StopIcon({super.key, this.color, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _StopIconPainter(
        color: color ?? IconTheme.of(context).color ?? Colors.black,
      ),
    );
  }
}

class _StopIconPainter extends CustomPainter {
  final Color color;

  _StopIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);

    final radius = size.width * 0.40;

    // Kreis
    canvas.drawCircle(center, radius, paint);

    // Stop-Quadrat
    final squareSize = size.width * 0.28;

    final square = Rect.fromCenter(
      center: center,
      width: squareSize,
      height: squareSize,
    );

    canvas.drawRect(square, paint);
  }

  @override
  bool shouldRepaint(covariant _StopIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
