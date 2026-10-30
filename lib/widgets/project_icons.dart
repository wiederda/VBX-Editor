import 'package:flutter/material.dart';

class OpenFolderIcon extends StatelessWidget {
  final Color? color;
  final double size;

  const OpenFolderIcon({super.key, this.color, this.size = 20});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _OpenFolderPainter(
      color: color ?? IconTheme.of(context).color ?? Colors.black,
    ),
  );
}

class ProjectTreeIcon extends StatelessWidget {
  final Color? color;
  final double size;

  const ProjectTreeIcon({super.key, this.color, this.size = 20});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _ProjectTreePainter(
      color: color ?? IconTheme.of(context).color ?? Colors.black,
    ),
  );
}

class ExplorerFolderIcon extends StatelessWidget {
  final Color? color;
  final double size;

  const ExplorerFolderIcon({super.key, this.color, this.size = 18});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _ExplorerFolderPainter(
      color: color ?? IconTheme.of(context).color ?? Colors.black,
    ),
  );
}

class ExplorerFileIcon extends StatelessWidget {
  final Color? color;
  final double size;

  const ExplorerFileIcon({super.key, this.color, this.size = 18});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _ExplorerFilePainter(
      color: color ?? IconTheme.of(context).color ?? Colors.black,
    ),
  );
}

class _OpenFolderPainter extends CustomPainter {
  final Color color;

  _OpenFolderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.085
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * 0.10, size.height * 0.29)
      ..lineTo(size.width * 0.41, size.height * 0.29)
      ..lineTo(size.width * 0.53, size.height * 0.41)
      ..lineTo(size.width * 0.88, size.height * 0.41)
      ..lineTo(size.width * 0.77, size.height * 0.79)
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height * 0.86,
        size.width * 0.67,
        size.height * 0.86,
      )
      ..lineTo(size.width * 0.13, size.height * 0.86)
      ..quadraticBezierTo(
        size.width * 0.08,
        size.height * 0.86,
        size.width * 0.09,
        size.height * 0.79,
      )
      ..close()
      ..moveTo(size.width * 0.10, size.height * 0.29)
      ..lineTo(size.width * 0.10, size.height * 0.20)
      ..quadraticBezierTo(
        size.width * 0.10,
        size.height * 0.15,
        size.width * 0.16,
        size.height * 0.15,
      )
      ..lineTo(size.width * 0.36, size.height * 0.15)
      ..lineTo(size.width * 0.48, size.height * 0.27);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _OpenFolderPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ProjectTreePainter extends CustomPainter {
  final Color color;

  _ProjectTreePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.085
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final nodePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final trunkX = size.width * 0.28;
    final branchX = size.width * 0.56;
    final rightX = size.width * 0.83;
    final topY = size.height * 0.20;
    final middleY = size.height * 0.50;
    final bottomY = size.height * 0.80;

    final branches = Path()
      ..moveTo(trunkX, topY + size.height * 0.04)
      ..lineTo(trunkX, bottomY - size.height * 0.04)
      ..moveTo(trunkX, middleY)
      ..lineTo(branchX, middleY)
      ..moveTo(branchX, topY)
      ..lineTo(branchX, bottomY)
      ..moveTo(branchX, topY)
      ..lineTo(rightX - size.width * 0.05, topY)
      ..moveTo(branchX, bottomY)
      ..lineTo(rightX - size.width * 0.05, bottomY);
    canvas.drawPath(branches, stroke);

    for (final point in [
      Offset(trunkX, topY),
      Offset(trunkX, middleY),
      Offset(trunkX, bottomY),
      Offset(rightX, topY),
      Offset(rightX, middleY),
      Offset(rightX, bottomY),
    ]) {
      canvas.drawCircle(point, size.width * 0.085, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ProjectTreePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ExplorerFolderPainter extends CustomPainter {
  final Color color;

  _ExplorerFolderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * 0.10, size.height * 0.30)
      ..lineTo(size.width * 0.41, size.height * 0.30)
      ..lineTo(size.width * 0.51, size.height * 0.42)
      ..lineTo(size.width * 0.88, size.height * 0.42)
      ..lineTo(size.width * 0.81, size.height * 0.80)
      ..quadraticBezierTo(
        size.width * 0.80,
        size.height * 0.87,
        size.width * 0.72,
        size.height * 0.87,
      )
      ..lineTo(size.width * 0.16, size.height * 0.87)
      ..quadraticBezierTo(
        size.width * 0.09,
        size.height * 0.87,
        size.width * 0.09,
        size.height * 0.79,
      )
      ..lineTo(size.width * 0.10, size.height * 0.30)
      ..moveTo(size.width * 0.10, size.height * 0.30)
      ..lineTo(size.width * 0.10, size.height * 0.19)
      ..quadraticBezierTo(
        size.width * 0.10,
        size.height * 0.14,
        size.width * 0.17,
        size.height * 0.14,
      )
      ..lineTo(size.width * 0.35, size.height * 0.14)
      ..lineTo(size.width * 0.48, size.height * 0.29);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ExplorerFolderPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ExplorerFilePainter extends CustomPainter {
  final Color color;

  _ExplorerFilePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.085
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final page = Path()
      ..moveTo(size.width * 0.22, size.height * 0.10)
      ..lineTo(size.width * 0.57, size.height * 0.10)
      ..lineTo(size.width * 0.80, size.height * 0.34)
      ..lineTo(size.width * 0.80, size.height * 0.88)
      ..lineTo(size.width * 0.22, size.height * 0.88)
      ..close()
      ..moveTo(size.width * 0.57, size.height * 0.11)
      ..lineTo(size.width * 0.57, size.height * 0.34)
      ..lineTo(size.width * 0.79, size.height * 0.34)
      ..moveTo(size.width * 0.34, size.height * 0.55)
      ..lineTo(size.width * 0.68, size.height * 0.55)
      ..moveTo(size.width * 0.34, size.height * 0.70)
      ..lineTo(size.width * 0.68, size.height * 0.70);
    canvas.drawPath(page, paint);
  }

  @override
  bool shouldRepaint(covariant _ExplorerFilePainter oldDelegate) =>
      oldDelegate.color != color;
}
