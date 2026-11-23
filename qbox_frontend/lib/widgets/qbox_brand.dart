import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The logo's colours, left to right: blue, teal, green.
const qboxBrandColors = [Color(0xFF0050DC), Color(0xFF038A86), Color(0xFF05AE10)];

/// "QBOX" in the logo's blue-to-green, used wherever the name appears in bold.
class QboxWordmark extends StatelessWidget {
  const QboxWordmark({this.fontSize = 34, this.letterSpacing = 0.6, this.textAlign, super.key});

  final double fontSize;
  final double letterSpacing;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => const LinearGradient(colors: qboxBrandColors).createShader(rect),
      child: Text(
        'QBOX',
        textAlign: textAlign,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: fontSize,
          height: 1,
          letterSpacing: letterSpacing,
          fontWeight: FontWeight.w800,
          color: Colors.white, // replaced by the gradient
        ),
      ),
    );
  }
}

/// The QBOX symbol: the Quadrant logo, sharp (traced from the original by
/// tool/make_splash_logo.dart).
///
/// [formed] 0..1 draws it like a pen along its own strokes, from the inner hook
/// ends beside the centre outward (both spirals at once). A second picture
/// holds WHEN each point is drawn; the logo is shown through it, so the logo
/// itself always stays sharp and unchanged.
class QboxSymbol extends StatefulWidget {
  const QboxSymbol({this.size = 120, this.formed = 1, super.key});

  final double size;
  final double formed;

  /// Loads the two pictures (once); the symbol shows when they are ready.
  static Future<(ui.Image, ui.Image)> load() => _loading ??= () async {
        Future<ui.Image> one(String name) async {
          final data = await rootBundle.load(name);
          final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
          return (await codec.getNextFrame()).image;
        }

        final pictures = (await one('assets/images/qbox_logo_lines.png'), await one('assets/images/qbox_logo_order.png'));
        _loaded = pictures;
        return pictures;
      }();

  static Future<(ui.Image, ui.Image)>? _loading;
  static (ui.Image, ui.Image)? _loaded;

  @override
  State<QboxSymbol> createState() => _QboxSymbolState();
}

class _QboxSymbolState extends State<QboxSymbol> {
  @override
  void initState() {
    super.initState();
    if (QboxSymbol._loaded == null) {
      QboxSymbol.load().then((_) {
        if (mounted) setState(() {});
      }, onError: (_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final pictures = QboxSymbol._loaded;
    return SizedBox.square(
      dimension: widget.size,
      child: pictures == null ? null : CustomPaint(painter: _SymbolPainter(pictures.$1, pictures.$2, widget.formed)),
    );
  }
}

class _SymbolPainter extends CustomPainter {
  _SymbolPainter(this.logo, this.order, this.formed);

  final ui.Image logo;
  final ui.Image order;
  final double formed;

  /// Sharpness of the pen tip (higher = crisper).
  static const _sharp = 60.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (formed <= 0) return;
    final dst = Offset.zero & size;
    Rect all(ui.Image i) => Rect.fromLTWH(0, 0, i.width.toDouble(), i.height.toDouble());
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = true;
    if (formed >= 1) {
      canvas.drawImageRect(logo, all(logo), dst, paint);
      return;
    }
    final threshold = 255 * (1 - formed);
    // Separate layers (not one paint with both a filter and a blend: phones
    // using Impeller then draw the time picture's colours on top).
    canvas.saveLayer(dst, Paint());
    canvas.drawImageRect(logo, all(logo), dst, paint);
    canvas.saveLayer(dst, Paint()..blendMode = BlendMode.dstIn); // keeps the logo only where drawn
    canvas.saveLayer(
      dst,
      Paint()
        ..colorFilter = ColorFilter.matrix([
          0, 0, 0, 0, 0, //
          0, 0, 0, 0, 0, //
          0, 0, 0, 0, 0, //
          // The time is red + green/256 (see tool/make_splash_logo.dart).
          _sharp, _sharp / 256, 0, 0, -_sharp * threshold,
        ]),
    );
    canvas.drawImageRect(order, all(order), dst, Paint()..filterQuality = FilterQuality.low);
    canvas.restore();
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SymbolPainter old) => old.formed != formed || old.logo != logo;
}
