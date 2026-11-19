import 'package:flutter/material.dart';

import 'signup_route.dart';

/// Makes a home-screen tile tappable. It grows a little while pressed, so the
/// tap is clearly felt. Tiles whose feature is built open [opens]; the rest
/// say the feature is coming soon.
class ToolTap extends StatefulWidget {
  const ToolTap({
    required this.label,
    required this.child,
    this.opens,
    super.key,
  });

  final String label;
  final WidgetBuilder? opens;
  final Widget child;

  @override
  State<ToolTap> createState() => _ToolTapState();
}

class _ToolTapState extends State<ToolTap> {
  static const _grow = Duration(milliseconds: 120);

  bool _pressed = false;
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 1.08 : 1,
      duration: _grow,
      curve: Curves.easeOutBack,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: Key('tool-${widget.label}'),
                splashColor: const Color(0x22651CE4),
                highlightColor: const Color(0x0F651CE4),
                onHighlightChanged: (down) {
                  if (!_opening) setState(() => _pressed = down);
                },
                onTap: _open,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open() async {
    if (_opening) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final builder = widget.opens;

    // Show the grow effect fully before moving on, even for a quick tap.
    setState(() {
      _opening = true;
      _pressed = true;
    });
    await Future<void>.delayed(_grow);
    if (!mounted) return;
    setState(() {
      _opening = false;
      _pressed = false;
    });

    if (builder != null) {
      // Any message from the home screen must not cover the new screen's buttons.
      messenger.hideCurrentSnackBar();
      await navigator.push(signupRoute(builder(context)));
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${widget.label} is coming soon'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}
