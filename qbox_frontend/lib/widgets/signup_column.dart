import 'package:flutter/material.dart';

/// Scrolls signup content when it is taller than the screen.
/// Groups stay together, so a short page does not leave a gap before the button.
class SignupColumn extends StatelessWidget {
  const SignupColumn({
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 108),
    this.spread = false,
    this.center = false,
    super.key,
  });

  final List<Widget> children;
  final EdgeInsets padding;

  /// Equal gaps between the children, from the top of the screen to the button.
  final bool spread;

  /// Puts the children in the middle of the screen.
  final bool center;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: padding,
              child: Column(
                mainAxisAlignment: spread
                    ? MainAxisAlignment.spaceBetween
                    : center
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        );
      },
    );
  }
}
