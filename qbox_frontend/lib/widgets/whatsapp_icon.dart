import 'package:flutter/material.dart';

/// A green speech bubble with a phone in it, so a WhatsApp button is not
/// mistaken for a message (SMS) one.
class WhatsAppIcon extends StatelessWidget {
  const WhatsAppIcon({this.size = 26, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: const _Bubble(),
        child: Center(
          child: Icon(Icons.call_rounded, color: Colors.white, size: size * 0.54),
        ),
      ),
    );
  }
}

class _Bubble extends CustomPainter {
  const _Bubble();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF25D366);
    final s = size.width;
    canvas.drawCircle(Offset(s / 2, s / 2), s * 0.47, paint);
    // The little tail at the bottom left.
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.07, s * 0.58)
        ..lineTo(s * 0.01, s * 0.99)
        ..lineTo(s * 0.42, s * 0.90)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(_Bubble oldDelegate) => false;
}
