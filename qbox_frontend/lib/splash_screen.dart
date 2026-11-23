import 'dart:math';

import 'package:flutter/material.dart';

import 'widgets/qbox_brand.dart';

export 'widgets/qbox_brand.dart' show QboxSymbol, QboxWordmark;

/// The opening animation: the Quadrant logo draws itself like a pen along its
/// own strokes (from the two inner hooks outward to the outer loops), then
/// "QBOX — powered by Quadrant IT Services", held for 1.5 seconds (3.5 s in all). [next] (login, or the role choice when
/// logged in) gets ready underneath meanwhile, so it is there when this fades.
class SplashScreen extends StatefulWidget {
  const SplashScreen({required this.next, this.duration = const Duration(milliseconds: 3500), super.key});

  final Widget next;
  final Duration duration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  bool _gone = false;

  // Parts of the 3.5-second timeline (0 = start, 1 = end): the lines draw in
  // order (0.1–1.4 s), a small "click" when the symbol is complete, the words
  // are all in by 2 s, then everything stays on screen for 1.5 seconds.
  late final _build = CurvedAnimation(parent: _c, curve: const Interval(0.03, 0.40, curve: Curves.easeInOutSine));
  late final _click = CurvedAnimation(parent: _c, curve: const Interval(0.39, 0.47));
  late final _title = CurvedAnimation(parent: _c, curve: const Interval(0.42, 0.52, curve: Curves.easeOutCubic));
  late final _byline = CurvedAnimation(parent: _c, curve: const Interval(0.48, 0.58, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(() => _fade.forward().whenComplete(() {
          if (mounted) setState(() => _gone = true);
        }));
  }

  @override
  void dispose() {
    _c.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.next,
        if (!_gone)
          IgnorePointer(
            child: FadeTransition(opacity: ReverseAnimation(_fade), child: _splash(context)),
          ),
      ],
    );
  }

  Widget _splash(BuildContext context) {
    final side = min(MediaQuery.of(context).size.width * 0.58, 270.0);
    return Scaffold(
      key: const Key('splash'),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFEFF8FD)],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: 1 + 0.05 * sin(pi * _click.value),
                  child: QboxSymbol(size: side, formed: _build.value),
                ),
                const SizedBox(height: 22),
                Opacity(
                  opacity: _title.value,
                  child: Transform.translate(
                    offset: Offset(0, 16 * (1 - _title.value)),
                    child: const QboxWordmark(fontSize: 42, letterSpacing: 3),
                  ),
                ),
                const SizedBox(height: 10),
                Opacity(
                  opacity: _byline.value,
                  child: const Text.rich(
                    TextSpan(
                      text: 'powered by ',
                      children: [
                        TextSpan(text: 'Quadrant IT Services', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1C0E57))),
                      ],
                    ),
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Color(0xFF5C5872)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
