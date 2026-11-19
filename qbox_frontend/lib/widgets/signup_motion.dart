import 'package:flutter/material.dart';

/// One finite entrance shared by the pieces of a signup screen.
class SignupMotionHost extends StatefulWidget {
  const SignupMotionHost({required this.child, super.key});

  final Widget child;

  @override
  State<SignupMotionHost> createState() => _SignupMotionHostState();
}

class _SignupMotionHostState extends State<SignupMotionHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    )..forward();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SignupMotion(animation: _motion, child: widget.child);
  }
}

class SignupMotion extends InheritedWidget {
  const SignupMotion({
    required this.animation,
    required super.child,
    super.key,
  });

  final Animation<double> animation;

  static Animation<double>? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SignupMotion>()?.animation;
  }

  @override
  bool updateShouldNotify(SignupMotion oldWidget) =>
      oldWidget.animation != animation;
}

/// Fades, rises, and settles a signup piece. Later indexes wait their turn.
/// If the screen entrance has already finished, the child appears at once.
class RiseIn extends StatefulWidget {
  const RiseIn({required this.index, required this.child, super.key});

  final int index;
  final Widget child;

  @override
  State<RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<RiseIn> {
  Animation<double>? _motion;
  CurvedAnimation? _curved;
  int? _index;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = SignupMotion.maybeOf(context);
    if (next == _motion && widget.index == _index) return;
    _curved?.dispose();
    _curved = null;
    _motion = next;
    _index = widget.index;
    if (next == null || next.status == AnimationStatus.completed) return;
    final start = (widget.index * 0.07).clamp(0.0, 0.7);
    final end = (start + 0.4).clamp(start + 0.05, 1.0);
    _curved = CurvedAnimation(
      parent: next,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _curved?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = _curved;
    if (curved == null) return widget.child;
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          alignment: Alignment.topCenter,
          child: widget.child,
        ),
      ),
    );
  }
}
