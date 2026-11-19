import 'package:flutter/material.dart';

/// Opens the next page immediately, with no slide or fade.
Route<void> signupRoute(Widget page, {String? name}) {
  return PageRouteBuilder<void>(
    settings: RouteSettings(name: name),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return child;
    },
  );
}
