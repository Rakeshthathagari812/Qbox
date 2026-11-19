import 'package:flutter/material.dart';

/// Corner brackets around four hollow squares. Used for Payments and My QR.
class QrMark extends StatelessWidget {
  const QrMark({this.size = 32, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: const QrMarkPainter(),
    );
  }
}

class QrMarkPainter extends CustomPainter {
  const QrMarkPainter();

  static const _purple = Color(0xFF651CE4);

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final stroke = side * 0.105;
    final bracket = Paint()
      ..color = _purple
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final pad = stroke * 0.55;
    final arm = side * 0.25;
    void corner(double x, double y, double hx, double vy) {
      canvas.drawPath(
        Path()
          ..moveTo(x + hx * arm, y)
          ..lineTo(x, y)
          ..lineTo(x, y + vy * arm),
        bracket,
      );
    }

    corner(pad, pad, 1, 1);
    corner(side - pad, pad, -1, 1);
    corner(pad, side - pad, 1, -1);
    corner(side - pad, side - pad, -1, -1);

    final origin = side * 0.255;
    final span = side * 0.49;
    final gap = side * 0.045;
    final cell = (span - gap) / 2;
    final fill = Paint()..color = _purple;
    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 2; col++) {
        final rect = Rect.fromLTWH(
          origin + col * (cell + gap),
          origin + row * (cell + gap),
          cell,
          cell,
        );
        final outer = RRect.fromRectAndRadius(
          rect,
          Radius.circular(cell * 0.30),
        );
        final inner = RRect.fromRectAndRadius(
          rect.deflate(cell * 0.30),
          Radius.circular(cell * 0.16),
        );
        canvas.drawPath(
          Path()
            ..fillType = PathFillType.evenOdd
            ..addRRect(outer)
            ..addRRect(inner),
          fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
