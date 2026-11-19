import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'widgets/qbox_wave.dart';
import 'widgets/signup_column.dart';

/// Last signup screen, shown once the backend has created the account.
/// "Log in" returns to the first page.
class SignupSuccessScreen extends StatefulWidget {
  const SignupSuccessScreen({super.key});

  @override
  State<SignupSuccessScreen> createState() => _SignupSuccessScreenState();
}

class _SignupSuccessScreenState extends State<SignupSuccessScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Animation<double> _span(double start, double end, Curve curve) {
    return CurvedAnimation(
      parent: _intro,
      curve: Interval(start, end, curve: curve),
    );
  }

  @override
  Widget build(BuildContext context) {
    final check = _span(0, 0.55, Curves.elasticOut);
    final burst = _span(0.05, 0.8, Curves.easeOut);
    final title = _span(0.22, 0.62, Curves.easeOutCubic);
    final card = _span(0.4, 0.82, Curves.easeOutCubic);
    final button = _span(0.62, 1, Curves.easeOutCubic);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F4FF),
      body: Stack(
        children: [
          const Align(
            alignment: Alignment.bottomCenter,
            child: QboxWaveFooter(),
          ),
          SafeArea(
            bottom: false,
            child: SignupColumn(
              center: true,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 108),
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                SizedBox(
                  height: 200,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: burst,
                        builder: (context, child) {
                          return CustomPaint(
                            size: const Size(220, 160),
                            painter: _BurstPainter(burst.value),
                          );
                        },
                      ),
                      ScaleTransition(
                        scale: Tween<double>(begin: 0.2, end: 1).animate(check),
                        child: const Image(
                          image: AssetImage('assets/images/art_success.png'),
                          height: 148,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                FadeTransition(
                  opacity: title,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.2),
                      end: Offset.zero,
                    ).animate(title),
                    child: const Text(
                      'Successfully Signed Up!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 26,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FadeTransition(
                  opacity: title,
                  child: const Text(
                    'Your account has been created and\nyour mobile number is verified.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                      color: _body,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                FadeTransition(
                  opacity: card,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.15),
                      end: Offset.zero,
                    ).animate(card),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3EEFF),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lock_outline, color: _purple, size: 28),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Your Account is Ready',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _ink,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'You can now log in to your QBOX account using your mobile number and 4-digit PIN.',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    height: 1.4,
                                    fontWeight: FontWeight.w500,
                                    color: _body,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FadeTransition(
                  opacity: button,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7C4DFF), Color(0xFF5B21E6)],
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: const Key('signup-login'),
                        onTap: () {
                          Navigator.of(context).popUntil(
                            (route) => route.isFirst,
                          );
                        },
                        borderRadius: BorderRadius.circular(28),
                        child: const SizedBox(
                          height: 52,
                          width: double.infinity,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Log in to Your Account',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(
                                  Icons.arrow_forward,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  const _BurstPainter(this.t);

  final double t;

  static const _colors = [
    Color(0xFFFFB703),
    Color(0xFF7C4DFF),
    Color(0xFF22C55E),
    Color(0xFFFB7185),
    Color(0xFF38BDF8),
    Color(0xFFF59E0B),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 12; i++) {
      final angle = (i / 12) * math.pi * 2 + 0.2;
      final distance = 18 + 62 * t;
      final spot = center + Offset(math.cos(angle), math.sin(angle)) * distance;
      paint.color = _colors[i % _colors.length].withValues(alpha: (1 - t).clamp(0, 1));
      canvas.save();
      canvas.translate(spot.dx, spot.dy);
      canvas.rotate(angle + t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: i.isEven ? 10 : 6,
            height: 3.5,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPainter oldDelegate) => oldDelegate.t != t;
}

const _ink = Color(0xFF1C0E57);
const _body = Color(0xFF5C5872);
const _purple = Color(0xFF651CE4);
