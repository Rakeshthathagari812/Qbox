import 'package:flutter/material.dart';

import 'widgets/qbox_brand.dart';

import 'login_screen.dart';
import 'otp_screen.dart';
import 'widgets/qbox_wave.dart';
import 'widgets/signup_motion.dart';
import 'widgets/signup_route.dart';

/// First screen of QBOX, matched to the page 1 reference.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const _ink = Color(0xFF1C0E57);
  static const _heading = Color(0xFF231D49);
  static const _body = Color(0xFF3A3558);
  static const _muted = Color(0xFFA39EB8);
  static const _secondary = Color(0xFF3A3C4E);
  static const _line = Color(0xFFD5D0E6);
  static const _lavender = Color(0xFFF4F0FD);
  static const _purple = Color(0xFF651CE4);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          const Align(
            alignment: Alignment.bottomCenter,
            child: QboxWaveFooter(),
          ),
          SafeArea(
            bottom: false,
            child: SignupMotionHost(
              child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ColoredBox(
                          color: _lavender,
                          child: Column(
                          children: [
                        const RiseIn(index: 0, child: _BrandHeader()),
                        const RiseIn(
                          index: 1,
                          child: Stack(
                            children: [
                              Image(
                                image: AssetImage('assets/images/hero_shop.png'),
                                width: double.infinity,
                                fit: BoxFit.fitWidth,
                              ),
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                height: 28,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        _lavender,
                                        Color(0x00F4F0FD),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                          ],
                        ),
                        ),
                        const SizedBox(height: 16),
                        const RiseIn(
                          index: 2,
                          child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            children: [
                              Text(
                                'Manage your business, payments, Udhaar,',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14.5,
                                  height: 1.45,
                                  fontWeight: FontWeight.w500,
                                  color: _body,
                                ),
                              ),
                              Text.rich(
                                TextSpan(
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 14.5,
                                    height: 1.45,
                                    fontWeight: FontWeight.w500,
                                    color: _body,
                                  ),
                                  children: [
                                    TextSpan(text: 'stock and more — '),
                                    TextSpan(
                                      text: 'all in one place.',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: _heading,
                                      ),
                                    ),
                                  ],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        ),
                        const SizedBox(height: 20),
                        RiseIn(
                          index: 3,
                          child: Padding(
                          padding: const EdgeInsets.only(bottom: 96),
                          child: Column(
                            children: [
                        const Text(
                          'Get started with QBOX',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _heading,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 52),
                          child: SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: _purple,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: const StadiumBorder(),
                                textStyle: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onPressed: () {
                                Navigator.of(context).push(
                                  signupRoute(const LoginScreen(), name: 'login'),
                                );
                              },
                              child: const Text('Log in'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              signupRoute(const OtpScreen()),
                            );
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: _secondary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          child: const Text.rich(
                            TextSpan(
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              children: [
                                TextSpan(text: 'New user? '),
                                TextSpan(
                                  text: 'Sign up',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: _purple,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                            ],
                          ),
                        ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: WelcomeScreen._lavender,
      padding: const EdgeInsets.fromLTRB(28, 44, 28, 14),
      child: const Column(
        children: [
          QboxWordmark(fontSize: 40, letterSpacing: 1.4),
          SizedBox(height: 8),
          Text(
            'Your Business. Simplified.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: WelcomeScreen._heading,
            ),
          ),
          SizedBox(height: 16),
          _PoweredBy(),
          SizedBox(height: 14),
          _QuadrantMark(),
        ],
      ),
    );
  }
}

class _QuadrantMark extends StatelessWidget {
  const _QuadrantMark();

  @override
  Widget build(BuildContext context) {
    return const FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image(
            image: AssetImage('assets/images/quadrant_logo.png'),
            height: 34,
            fit: BoxFit.contain,
          ),
          SizedBox(width: 10),
          Text(
            'Quadrant IT Services',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: WelcomeScreen._ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _PoweredBy extends StatelessWidget {
  const _PoweredBy();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: _Hairline()),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Powered by',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: WelcomeScreen._muted,
            ),
          ),
        ),
        Expanded(child: _Hairline()),
      ],
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: WelcomeScreen._line);
  }
}

