// Saves the QBOX symbol (finished, and half drawn) as pictures, to check it:
//   flutter test test/render_symbol_test.dart --dart-define=SYMBOL_OUT=<folder>
// Does nothing in normal test runs.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/widgets/qbox_brand.dart';

void main() {
  const out = String.fromEnvironment('SYMBOL_OUT');

  for (final (name, formed) in [('symbol_full', 1.0), ('symbol_half', 0.5)]) {
    testWidgets('render $name', (tester) async {
      if (out.isEmpty) return;
      // Load the pictures with real time first (in test time they never finish).
      await tester.runAsync(QboxSymbol.load);
      final key = GlobalKey();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(color: Colors.white, child: QboxSymbol(size: 600, formed: formed)),
          ),
        ),
      ));
      await tester.pump();
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    });
  }
}
