// Makes the app icon images from assets/branding/qbox_icon_source.png.
// (The splash logo is made separately by tool/make_splash_logo.dart.)
//
// Run from the qbox_frontend folder:
//   dart run tool/make_brand_images.dart
//   dart run flutter_launcher_icons
//
// Outputs:
//   assets/branding/qbox_icon.png             the full icon, black corners made see-through
//   assets/branding/qbox_icon_foreground.png  the design sized for Android's shaped icons
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

void main() {
  final source = img.decodePng(File('assets/branding/qbox_icon_source.png').readAsBytesSync())!;

  // 1. Full icon: the black outside the rounded frame becomes see-through.
  final full = img.Image(width: source.width, height: source.height, numChannels: 4);
  for (final p in source) {
    full.setPixelRgba(p.x, p.y, p.r, p.g, p.b, 255);
  }
  _clearFrom(full, [(0, 0), (full.width - 1, 0), (0, full.height - 1), (full.width - 1, full.height - 1)]);
  _save(img.copyResize(full, width: 1024, interpolation: img.Interpolation.average), 'assets/branding/qbox_icon.png');

  // 2. Shaped icon: the whole design (border, light background, logo) filling
  //    the icon. Android shows only the middle 66% (683 of 1024) through the
  //    launcher's shape, so the design is made a little bigger than that: its
  //    blue-green border then runs along the edge of the icon shape.
  final fg = img.Image(width: 1024, height: 1024, numChannels: 4);
  const size = 740;
  final scaled = img.copyResize(full, width: size, interpolation: img.Interpolation.average);
  img.compositeImage(fg, scaled, dstX: (1024 - size) ~/ 2, dstY: (1024 - size) ~/ 2);
  _save(fg, 'assets/branding/qbox_icon_foreground.png');
}

/// Makes near-black pixels joined to [starts] see-through (flood fill).
void _clearFrom(img.Image image, List<(int, int)> starts) {
  final seen = List<bool>.filled(image.width * image.height, false);
  final stack = [...starts];
  while (stack.isNotEmpty) {
    final (x, y) = stack.removeLast();
    if (x < 0 || y < 0 || x >= image.width || y >= image.height) continue;
    final i = y * image.width + x;
    if (seen[i]) continue;
    seen[i] = true;
    final p = image.getPixel(x, y);
    final light = max(p.r, max(p.g, p.b));
    if (light > 70) continue; // reached the coloured frame
    image.setPixelRgba(x, y, 0, 0, 0, 0);
    stack.addAll([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]);
  }
}

void _save(img.Image image, String path) {
  File(path).writeAsBytesSync(img.encodePng(image));
  stdout.writeln('wrote $path (${image.width}x${image.height})');
}
