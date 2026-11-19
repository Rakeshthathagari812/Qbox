import 'package:flutter/material.dart';

class QboxWaveFooter extends StatefulWidget {
  const QboxWaveFooter({super.key});

  @override
  State<QboxWaveFooter> createState() => _QboxWaveFooterState();
}

class _QboxWaveFooterState extends State<QboxWaveFooter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rise;
  late final CurvedAnimation _curved;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _rise = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _curved = CurvedAnimation(parent: _rise, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.45),
      end: Offset.zero,
    ).animate(_curved);
  }

  @override
  void dispose() {
    _curved.dispose();
    _rise.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curved,
      child: SlideTransition(
        position: _slide,
        child: const SizedBox(
          height: 128,
          width: double.infinity,
          child: CustomPaint(painter: _WavePainter()),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    final back = Path()
      ..moveTo(0, height * 0.58)
      ..cubicTo(
        width * 0.16,
        height * 0.18,
        width * 0.34,
        height * 0.92,
        width * 0.58,
        height * 0.50,
      )
      ..cubicTo(
        width * 0.78,
        height * 0.16,
        width * 0.90,
        height * 0.34,
        width,
        height * 0.46,
      )
      ..lineTo(width, height)
      ..lineTo(0, height)
      ..close();
    canvas.drawPath(back, Paint()..color = const Color(0xFFB898FC));

    final front = Path()
      ..moveTo(0, height * 0.74)
      ..cubicTo(
        width * 0.20,
        height * 0.34,
        width * 0.42,
        height * 0.98,
        width * 0.68,
        height * 0.62,
      )
      ..cubicTo(
        width * 0.84,
        height * 0.40,
        width * 0.94,
        height * 0.52,
        width,
        height * 0.60,
      )
      ..lineTo(width, height)
      ..lineTo(0, height)
      ..close();
    canvas.drawPath(front, Paint()..color = const Color(0xFFD6C6FD));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
