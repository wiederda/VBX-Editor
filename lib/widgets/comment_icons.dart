import 'package:flutter/material.dart';

class CommentIcon extends StatelessWidget {
  final bool uncomment;
  final Color? color;
  final double size;

  const CommentIcon({
    super.key,
    required this.uncomment,
    this.color,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _CommentIconPainter(
        color: color ?? IconTheme.of(context).color ?? Colors.black,
        uncomment: uncomment,
      ),
    );
  }
}

class _CommentIconPainter extends CustomPainter {
  final Color color;
  final bool uncomment;

  _CommentIconPainter({required this.color, required this.uncomment});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final left = size.width * 0.12;
    final right = size.width * 0.88;

    // Drei Textzeilen
    for (var i = 0; i < 3; i++) {
      final y = size.height * (0.25 + i * 0.25);

      canvas.drawLine(Offset(left, y), Offset(right, y), paint);
    }

    if (uncomment) {
      _drawUncommentArrow(canvas, size, paint);
    } else {
      _drawCommentMarks(canvas, size, paint);
    }
  }

  void _drawCommentMarks(Canvas canvas, Size size, Paint paint) {
    // Zwei kleine Schrägstriche vor den Zeilen.
    final x = size.width * 0.10;

    canvas.drawLine(
      Offset(x, size.height * 0.16),
      Offset(x + size.width * 0.10, size.height * 0.34),
      paint,
    );

    canvas.drawLine(
      Offset(x + size.width * 0.08, size.height * 0.16),
      Offset(x + size.width * 0.18, size.height * 0.34),
      paint,
    );
  }

  void _drawUncommentArrow(Canvas canvas, Size size, Paint paint) {
    final path = Path();

    path.moveTo(size.width * 0.78, size.height * 0.18);

    path.cubicTo(
      size.width * 0.92,
      size.height * 0.20,
      size.width * 0.92,
      size.height * 0.48,
      size.width * 0.68,
      size.height * 0.48,
    );

    path.cubicTo(
      size.width * 0.52,
      size.height * 0.48,
      size.width * 0.52,
      size.height * 0.68,
      size.width * 0.72,
      size.height * 0.76,
    );

    canvas.drawPath(path, paint);

    // Pfeilspitze
    final arrow = Path()
      ..moveTo(size.width * 0.68, size.height * 0.67)
      ..lineTo(size.width * 0.72, size.height * 0.76)
      ..lineTo(size.width * 0.62, size.height * 0.78);

    canvas.drawPath(arrow, paint);
  }

  @override
  bool shouldRepaint(covariant _CommentIconPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.uncomment != uncomment;
  }
}
