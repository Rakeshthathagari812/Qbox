import 'dart:math' as math;

import 'package:flutter/material.dart';

/// On a wide screen, shows the app inside a phone instead of stretching it.
class PhoneStage extends StatelessWidget {
  const PhoneStage({required this.child, super.key});

  final Widget child;

  static const _screenWidth = 390.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 520 &&
            constraints.maxWidth.isFinite &&
            constraints.maxHeight.isFinite;
        if (!wide) return child;

        const bezel = 14.0;
        final screenHeight = math.min(
          844.0,
          constraints.maxHeight - 32 - bezel * 2,
        );
        return ColoredBox(
          color: const Color(0xFFD9D4E8),
          child: Center(
            child: _Phone(
              screenWidth: _screenWidth,
              screenHeight: screenHeight,
              bezel: bezel,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _Phone extends StatelessWidget {
  const _Phone({
    required this.screenWidth,
    required this.screenHeight,
    required this.bezel,
    required this.child,
  });

  final double screenWidth;
  final double screenHeight;
  final double bezel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: screenWidth + bezel * 2,
      height: screenHeight + bezel * 2,
      decoration: BoxDecoration(
        color: const Color(0xFF16141F),
        borderRadius: BorderRadius.circular(40),
        boxShadow: const [
          BoxShadow(
            color: Color(0x551C0E57),
            blurRadius: 36,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(bezel),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: Size(screenWidth, screenHeight),
                ),
                child: SizedBox(
                  width: screenWidth,
                  height: screenHeight,
                  child: child,
                ),
              ),
            ),
          ),
          Positioned(
            top: 5,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 78,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3844),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
