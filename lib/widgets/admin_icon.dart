import 'package:flutter/material.dart';

class AdminIcon extends StatelessWidget {
  final Color? color;
  final double size;

  const AdminIcon({super.key, this.color, this.size = 24});

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? IconTheme.of(context).color;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _AdminIconPainter(color: iconColor)),
    );
  }
}

class _AdminIconPainter extends CustomPainter {
  final Color? color;

  _AdminIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color ?? Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = color ?? Colors.black
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // ------------------------------------------------------------
    // Benutzerkopf
    // ------------------------------------------------------------

    final headCenter = Offset(w * 0.50, h * 0.29);
    final headRadius = w * 0.115;

    canvas.drawCircle(headCenter, headRadius, fillPaint);

    // ------------------------------------------------------------
    // Benutzerkörper
    // ------------------------------------------------------------

    final bodyPath = Path();

    bodyPath.moveTo(w * 0.25, h * 0.68);
    bodyPath.cubicTo(
      w * 0.25,
      h * 0.49,
      w * 0.36,
      h * 0.40,
      w * 0.50,
      h * 0.40,
    );

    bodyPath.cubicTo(
      w * 0.64,
      h * 0.40,
      w * 0.75,
      h * 0.49,
      w * 0.75,
      h * 0.68,
    );

    bodyPath.lineTo(w * 0.25, h * 0.68);
    bodyPath.close();

    canvas.drawPath(bodyPath, fillPaint);

    // ------------------------------------------------------------
    // Schutzschild / Administrator
    // ------------------------------------------------------------

    final shieldPath = Path();

    shieldPath.moveTo(w * 0.63, h * 0.47);

    shieldPath.lineTo(w * 0.86, h * 0.53);

    shieldPath.lineTo(w * 0.86, h * 0.68);

    shieldPath.cubicTo(
      w * 0.86,
      h * 0.82,
      w * 0.76,
      h * 0.91,
      w * 0.63,
      h * 0.96,
    );

    shieldPath.cubicTo(
      w * 0.50,
      h * 0.91,
      w * 0.40,
      h * 0.82,
      w * 0.40,
      h * 0.68,
    );

    shieldPath.lineTo(w * 0.40, h * 0.53);

    shieldPath.close();

    // Schild als gefüllte Fläche
    canvas.drawPath(shieldPath, fillPaint);

    // Schild innen wieder mit Hintergrundfarbe aufbauen,
    // damit das Symbol auch bei dunklem Theme sauber aussieht.
    final backgroundColor = color == Colors.white
        ? Colors.grey.shade900
        : Colors.white;

    final innerPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;

    final innerShield = Path();

    innerShield.moveTo(w * 0.63, h * 0.53);
    innerShield.lineTo(w * 0.80, h * 0.57);
    innerShield.lineTo(w * 0.80, h * 0.68);

    innerShield.cubicTo(
      w * 0.80,
      h * 0.77,
      w * 0.73,
      h * 0.84,
      w * 0.63,
      h * 0.88,
    );

    innerShield.cubicTo(
      w * 0.53,
      h * 0.84,
      w * 0.46,
      h * 0.77,
      w * 0.46,
      h * 0.68,
    );

    innerShield.lineTo(w * 0.46, h * 0.57);
    innerShield.close();

    canvas.drawPath(innerShield, innerPaint);

    // ------------------------------------------------------------
    // Häkchen im Schild
    // ------------------------------------------------------------

    final checkPaint = Paint()
      ..color = color ?? Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final checkPath = Path();

    checkPath.moveTo(w * 0.53, h * 0.70);
    checkPath.lineTo(w * 0.59, h * 0.76);
    checkPath.lineTo(w * 0.73, h * 0.62);

    canvas.drawPath(checkPath, checkPaint);
  }

  @override
  bool shouldRepaint(covariant _AdminIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
