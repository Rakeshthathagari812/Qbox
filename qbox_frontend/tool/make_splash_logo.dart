// Makes the sharp splash logo from the original Quadrant logo
// (assets/branding/qbox_logo_reference.png):
//   dart run tool/make_splash_logo.dart [preview.png]
//
// The original is small and soft (421 px), so enlarging it gives blurry,
// speckled lines. Instead its outline is traced: the edges are found, each
// straight edge is fitted with an exact straight line and the corners are
// where those lines meet. The traced shape is then drawn crisply at 1200 px,
// coloured with a smooth blend fitted to the original's own colours. The shape
// stays the original's (the script prints how far the new outline is from it).
//
// Outputs:
//   assets/images/qbox_logo_lines.png  the sharp logo (1200 x 1200)
//   assets/images/qbox_logo_order.png  WHEN each point is drawn (600 x 600):
//       red + green/256 = 255 first .. 10 last; alpha 0 = not part of the
//       logo. The splash shows the logo
//       through this, so it grows along its own strokes like a pen, from the
//       inner hook ends beside the centre outward (both spirals at once).
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

const out = 1200;

typedef P = ({double x, double y});

void main(List<String> args) {
  final png = img.decodePng(File('assets/branding/qbox_logo_reference.png').readAsBytesSync())!;
  // Flatten onto white (the picture's background is see-through).
  final raw = img.Image(width: png.width, height: png.height, numChannels: 3);
  for (final p in png) {
    final a = p.a / p.maxChannelValue;
    int mix(num c) => (255 * (1 - a) + c * a).round();
    raw.setPixelRgb(p.x, p.y, mix(p.r), mix(p.g), mix(p.b));
  }
  final ref = img.gaussianBlur(img.Image.from(raw), radius: 1);

  // How much of a pixel is logo (0..1). The logo colours all have one channel
  // near 0 and the background is white, so the darkest channel tells it,
  // whatever the colour.
  double logo(num r, num g, num b) => ((255 - min(r, min(g, b))) / 245).clamp(0.0, 1.0).toDouble();

  var left = ref.width, top = ref.height, right = 0, bottom = 0;
  for (final p in ref) {
    if (logo(p.r, p.g, p.b) < 0.5) continue;
    left = min(left, p.x);
    top = min(top, p.y);
    right = max(right, p.x);
    bottom = max(bottom, p.y);
  }
  final side = max(right - left, bottom - top) + 8;
  final cx = (left + right) / 2, cy = (top + bottom) / 2;
  final x0 = cx - side / 2, y0 = cy - side / 2;
  final scale = side / out;

  // 1. The logo amount on the 1200 grid (smooth enlargement).
  final field = List<double>.filled(out * out, 0);
  for (var y = 0; y < out; y++) {
    for (var x = 0; x < out; x++) {
      final p = ref.getPixelInterpolate(x0 + (x + 0.5) * scale - 0.5, y0 + (y + 0.5) * scale - 0.5,
          interpolation: img.Interpolation.cubic);
      field[y * out + x] = logo(p.r, p.g, p.b);
    }
  }

  // 2. The outline at half amount, then exact straight edges and corners.
  final all = _contours(field);
  final loops = all.where((l) => l.length > 200).toList();
  stdout.writeln('outlines found: ${all.length}, long: ${loops.length}, '
      'logo pixels: ${field.where((f) => f >= 0.5).length}');
  final shapes = [for (final l in loops) _straighten(l)];
  var worst = 0.0;
  for (var i = 0; i < loops.length; i++) {
    for (final p in loops[i]) {
      worst = max(worst, _distToPolygon(p, shapes[i]));
    }
    stdout.writeln('outline ${i + 1}: ${shapes[i].length} corners');
  }
  stdout.writeln('largest distance from the original outline: '
      '${worst.toStringAsFixed(1)} px of $out (${(worst * scale).toStringAsFixed(2)} px of the original)');

  // 3. Draw the traced shape sharply (exact coverage across, 8 rows per pixel).
  final cover = _fill(shapes);

  // 4. Colour: a smooth blend fitted to the original's colours.
  final fit = _fitColours(raw, logo, (sx, sy) => ((sx - x0) / scale, (sy - y0) / scale));
  final lines = img.Image(width: out, height: out, numChannels: 4);
  for (var y = 0; y < out; y++) {
    for (var x = 0; x < out; x++) {
      final a = cover[y * out + x];
      if (a <= 0) {
        lines.setPixelRgba(x, y, 0, 0, 0, 0);
        continue;
      }
      final c = fit(x + 0.5, y + 0.5);
      lines.setPixelRgba(x, y, c.$1, c.$2, c.$3, (a * 255).round());
    }
  }
  File('assets/images/qbox_logo_lines.png').writeAsBytesSync(img.encodePng(lines));
  stdout.writeln('wrote assets/images/qbox_logo_lines.png');

  // 5. Drawing order along each spiral, from its inner hook end.
  final order = _order(cover);
  File('assets/images/qbox_logo_order.png').writeAsBytesSync(img.encodePng(order));
  stdout.writeln('wrote assets/images/qbox_logo_order.png');

  if (args.isNotEmpty) _preview(raw, lines, order, args.first, (x0, y0, side));
}

// ---------------------------------------------------------------- outline

/// Closed outlines where [field] crosses 0.5 (marching squares).
List<List<P>> _contours(List<double> field) {
  const level = 0.5;
  double v(int x, int y) => field[y * out + x];
  // An edge point: horizontal edge (x,y)-(x+1,y) = 2*(y*out+x), vertical = +1.
  final pos = <int, P>{};
  final links = <int, List<int>>{};
  int edge(int x, int y, bool vertical) {
    final id = 2 * (y * out + x) + (vertical ? 1 : 0);
    pos.putIfAbsent(id, () {
      final a = v(x, y), b = vertical ? v(x, y + 1) : v(x + 1, y);
      final t = (level - a) / (b - a);
      return vertical ? (x: x + 0.5, y: y + t + 0.5) : (x: x + t + 0.5, y: y + 0.5);
    });
    return id;
  }

  void link(int a, int b) {
    (links[a] ??= []).add(b);
    (links[b] ??= []).add(a);
  }

  for (var y = 0; y < out - 1; y++) {
    for (var x = 0; x < out - 1; x++) {
      final c = (v(x, y) >= level ? 1 : 0) |
          (v(x + 1, y) >= level ? 2 : 0) |
          (v(x + 1, y + 1) >= level ? 4 : 0) |
          (v(x, y + 1) >= level ? 8 : 0);
      if (c == 0 || c == 15) continue;
      final top = (c & 1) != (c & 2) >> 1 ? edge(x, y, false) : -1;
      final rgt = ((c & 2) >> 1) != ((c & 4) >> 2) ? edge(x + 1, y, true) : -1;
      final bot = ((c & 8) >> 3) != ((c & 4) >> 2) ? edge(x, y + 1, false) : -1;
      final lft = (c & 1) != ((c & 8) >> 3) ? edge(x, y, true) : -1;
      final ends = [top, rgt, bot, lft].where((e) => e >= 0).toList();
      if (ends.length == 2) {
        link(ends[0], ends[1]);
      } else if (ends.length == 4) {
        // Saddle: keep the logo parts apart.
        if (c == 5) {
          link(top, lft);
          link(rgt, bot);
        } else {
          link(top, rgt);
          link(bot, lft);
        }
      }
    }
  }

  final seen = <int>{};
  final loops = <List<P>>[];
  for (final start in links.keys) {
    if (seen.contains(start)) continue;
    final loop = <P>[];
    var prev = -1, cur = start;
    while (!seen.contains(cur)) {
      seen.add(cur);
      loop.add(pos[cur]!);
      final next = links[cur]!.firstWhere((n) => n != prev && !seen.contains(n), orElse: () => -1);
      if (next < 0) break;
      prev = cur;
      cur = next;
    }
    loops.add(loop);
  }
  return loops;
}

/// The outline as exact straight edges: rough corners by Douglas–Peucker, then
/// each edge refitted to its outline points and the corners recomputed as the
/// meeting points of neighbouring edges. Tiny edges (blur at corners) go.
List<P> _straighten(List<P> loop) {
  final n = loop.length;
  // Rough corners.
  var far = 0;
  for (var i = 0; i < n; i++) {
    if (_dist(loop[0], loop[i]) > _dist(loop[0], loop[far])) far = i;
  }
  final idx = <int>[0, ..._dp(loop, 0, far, 3), far, ..._dp(loop, far, n, 3)];

  // Edges as index ranges, dropping tiny ones.
  var edges = <(int, int)>[];
  for (var i = 0; i < idx.length; i++) {
    final a = idx[i], b = i + 1 < idx.length ? idx[i + 1] : idx[0] + n;
    if (_dist(loop[a % n], loop[b % n]) >= 20) edges.add((a, b));
  }

  // Fit, merging neighbours that are (nearly) the same line.
  ({P c, P d}) fitEdge((int, int) e) {
    final len = e.$2 - e.$1;
    final trim = (len * 0.2).round();
    final pts = [for (var k = e.$1 + trim; k <= e.$2 - trim; k++) loop[k % n]];
    return _fitLine(pts.length >= 2 ? pts : [loop[e.$1 % n], loop[e.$2 % n]]);
  }

  var fits = edges.map(fitEdge).toList();
  for (var merged = true; merged;) {
    merged = false;
    for (var i = 0; i < edges.length && edges.length > 3; i++) {
      final j = (i + 1) % edges.length;
      final a = fits[i].d, b = fits[j].d;
      if ((a.x * b.y - a.y * b.x).abs() < sin(6 * pi / 180)) {
        final e = j == 0 ? (edges[i].$1, edges[j].$2 + n) : (edges[i].$1, edges[j].$2);
        edges[i] = e;
        fits[i] = fitEdge(e);
        edges.removeAt(j);
        fits.removeAt(j);
        merged = true;
        break;
      }
    }
  }
  return [
    for (var i = 0; i < fits.length; i++) _meet(fits[(i - 1 + fits.length) % fits.length], fits[i]),
  ];
}

List<int> _dp(List<P> loop, int a, int b, double eps) {
  final n = loop.length;
  final pa = loop[a % n], pb = loop[b % n];
  var best = -1;
  var bestD = eps;
  for (var k = a + 1; k < b; k++) {
    final d = _distToSegment(loop[k % n], pa, pb);
    if (d > bestD) {
      bestD = d;
      best = k;
    }
  }
  if (best < 0) return [];
  return [..._dp(loop, a, best, eps), best % n, ..._dp(loop, best, b, eps)];
}

/// Best straight line through [pts]: centre and unit direction.
({P c, P d}) _fitLine(List<P> pts) {
  var mx = 0.0, my = 0.0;
  for (final p in pts) {
    mx += p.x;
    my += p.y;
  }
  mx /= pts.length;
  my /= pts.length;
  var sxx = 0.0, sxy = 0.0, syy = 0.0;
  for (final p in pts) {
    sxx += (p.x - mx) * (p.x - mx);
    sxy += (p.x - mx) * (p.y - my);
    syy += (p.y - my) * (p.y - my);
  }
  final angle = 0.5 * atan2(2 * sxy, sxx - syy);
  return (c: (x: mx, y: my), d: (x: cos(angle), y: sin(angle)));
}

P _meet(({P c, P d}) a, ({P c, P d}) b) {
  final den = a.d.x * b.d.y - a.d.y * b.d.x;
  if (den.abs() < 1e-6) return b.c;
  final t = ((b.c.x - a.c.x) * b.d.y - (b.c.y - a.c.y) * b.d.x) / den;
  return (x: a.c.x + t * a.d.x, y: a.c.y + t * a.d.y);
}

double _dist(P a, P b) => sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));

double _distToSegment(P p, P a, P b) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final l2 = dx * dx + dy * dy;
  if (l2 == 0) return _dist(p, a);
  final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / l2).clamp(0.0, 1.0);
  return _dist(p, (x: a.x + t * dx, y: a.y + t * dy));
}

double _distToPolygon(P p, List<P> poly) {
  var best = double.infinity;
  for (var i = 0; i < poly.length; i++) {
    best = min(best, _distToSegment(p, poly[i], poly[(i + 1) % poly.length]));
  }
  return best;
}

// ---------------------------------------------------------------- drawing

/// Exact coverage (0..1) of the shapes (even–odd), 8 sample rows per pixel.
List<double> _fill(List<List<P>> shapes) {
  const rows = 8;
  final cover = List<double>.filled(out * out, 0);
  final edges = <(P, P)>[
    for (final s in shapes)
      for (var i = 0; i < s.length; i++) (s[i], s[(i + 1) % s.length]),
  ];
  for (var y = 0; y < out; y++) {
    for (var r = 0; r < rows; r++) {
      final sy = y + (r + 0.5) / rows;
      final xs = <double>[];
      for (final (a, b) in edges) {
        if ((a.y <= sy) != (b.y <= sy)) xs.add(a.x + (sy - a.y) / (b.y - a.y) * (b.x - a.x));
      }
      xs.sort();
      for (var k = 0; k + 1 < xs.length; k += 2) {
        final a = xs[k].clamp(0.0, out.toDouble()), b = xs[k + 1].clamp(0.0, out.toDouble());
        for (var px = a.floor(); px < b.ceil() && px < out; px++) {
          final overlap = min(b, px + 1.0) - max(a, px.toDouble());
          if (overlap > 0) cover[y * out + px] += overlap / rows;
        }
      }
    }
  }
  return cover;
}

/// A smooth colour blend (2nd-order in x and y, per channel) fitted to the
/// solid inside of the original logo.
(int, int, int) Function(double, double) _fitColours(
    img.Image raw, double Function(num, num, num) logo, (double, double) Function(double, double) toOut) {
  List<double> terms(double x, double y) {
    final u = x / out - 0.5, v = y / out - 0.5;
    return [1, u, v, u * u, u * v, v * v];
  }

  const k = 6;
  final ata = List.generate(k, (_) => List<double>.filled(k, 0));
  final atb = List.generate(3, (_) => List<double>.filled(k, 0));
  for (final p in raw) {
    if (logo(p.r, p.g, p.b) < 0.92) continue;
    final (x, y) = toOut(p.x + 0.5, p.y + 0.5);
    final t = terms(x, y);
    final c = [p.r.toDouble(), p.g.toDouble(), p.b.toDouble()];
    for (var i = 0; i < k; i++) {
      for (var j = 0; j < k; j++) {
        ata[i][j] += t[i] * t[j];
      }
      for (var ch = 0; ch < 3; ch++) {
        atb[ch][i] += t[i] * c[ch];
      }
    }
  }
  final coef = [for (var ch = 0; ch < 3; ch++) _solve(ata, atb[ch])];
  return (x, y) {
    final t = terms(x, y);
    int ch(int c) {
      var s = 0.0;
      for (var i = 0; i < k; i++) {
        s += coef[c][i] * t[i];
      }
      return s.round().clamp(0, 255);
    }

    return (ch(0), ch(1), ch(2));
  };
}

List<double> _solve(List<List<double>> a0, List<double> b0) {
  final n = b0.length;
  final a = [for (var i = 0; i < n; i++) [...a0[i], b0[i]]];
  for (var c = 0; c < n; c++) {
    var p = c;
    for (var r = c + 1; r < n; r++) {
      if (a[r][c].abs() > a[p][c].abs()) p = r;
    }
    final t = a[c];
    a[c] = a[p];
    a[p] = t;
    for (var r = 0; r < n; r++) {
      if (r == c) continue;
      final f = a[r][c] / a[c][c];
      for (var j = c; j <= n; j++) {
        a[r][j] -= f * a[c][j];
      }
    }
  }
  return [for (var i = 0; i < n; i++) a[i][n] / a[i][i]];
}

// ---------------------------------------------------------------- order

/// WHEN each point is drawn, as the alpha of a 600 x 600 picture.
img.Image _order(List<double> cover) {
  final label = List<int>.filled(out * out, 0);
  final pieces = <List<int>>[];
  for (var i = 0; i < out * out; i++) {
    if (label[i] != 0 || cover[i] < 0.5) continue;
    final id = pieces.length + 1;
    final members = <int>[];
    final queue = Queue<int>()..add(i);
    label[i] = id;
    while (queue.isNotEmpty) {
      final j = queue.removeFirst();
      members.add(j);
      for (final m in _neighbours(j)) {
        if (label[m] == 0 && cover[m] >= 0.5) {
          label[m] = id;
          queue.add(m);
        }
      }
    }
    if (members.length > 2000) pieces.add(members);
  }
  stdout.writeln('spirals: ${pieces.length}');

  final when = List<double>.filled(out * out, -1);
  const centre = out / 2;
  for (final members in pieces) {
    // The inner hook end: from the point nearest the centre, the farthest
    // point along the stroke is the outer end; from there, the farthest point
    // is the inner end.
    final id = label[members.first];
    final nearest = members.reduce((a, b) => _dc(a, centre) < _dc(b, centre) ? a : b);
    final first = _sweep(nearest, label, id);
    final outer = members.reduce((a, b) => first[a]! > first[b]! ? a : b);
    final fromOuter = _sweep(outer, label, id);
    final inner = members.reduce((a, b) => fromOuter[a]! > fromOuter[b]! ? a : b);
    final dist = _sweep(inner, label, id);
    final far = dist.values.reduce(max);
    stdout.writeln('spiral starts at (${inner % out}, ${inner ~/ out})');
    for (final m in members) {
      when[m] = dist[m]! / far;
    }
  }

  // Spread the times a little beyond the shape, so its soft edges are covered.
  for (var pass = 0; pass < 10; pass++) {
    final fill = <int, double>{};
    for (var i = 0; i < out * out; i++) {
      if (when[i] >= 0) continue;
      for (final m in _neighbours(i)) {
        if (when[m] >= 0) {
          fill[i] = when[m];
          break;
        }
      }
    }
    fill.forEach((i, t) => when[i] = t);
  }

  // Smooth the pen front: average the times nearby (same region only).
  final smooth = _blur(when, 6);

  // Time as a fine number: red = whole part, green = 1/256 parts, so the pen
  // tip moves smoothly (one channel alone has only 245 steps for the path).
  // Alpha marks where the logo is (255) or not (0).
  final half = out ~/ 2;
  final order = img.Image(width: half, height: half, numChannels: 4);
  for (var y = 0; y < half; y++) {
    for (var x = 0; x < half; x++) {
      var sum = 0.0, count = 0;
      for (final i in [(2 * y) * out + 2 * x, (2 * y) * out + 2 * x + 1, (2 * y + 1) * out + 2 * x, (2 * y + 1) * out + 2 * x + 1]) {
        if (smooth[i] >= 0) {
          sum += smooth[i];
          count++;
        }
      }
      if (count == 0) {
        order.setPixelRgba(x, y, 0, 0, 0, 0);
        continue;
      }
      final v = 255 - sum / count * 245; // 255 = first .. 10 = last
      final whole = v.floor().clamp(0, 255);
      final part = ((v - whole) * 256).floor().clamp(0, 255);
      order.setPixelRgba(x, y, whole, part, 0, 255);
    }
  }
  return order;
}

/// Box blur of the times (radius [r]), counting only places that have one.
List<double> _blur(List<double> v, int r) {
  List<double> pass(List<double> src, bool across) {
    final dst = List<double>.filled(out * out, -1);
    for (var a = 0; a < out; a++) {
      var sum = 0.0, count = 0;
      int at(int b) => across ? a * out + b : b * out + a;
      for (var b = 0; b < r; b++) {
        if (src[at(b)] >= 0) {
          sum += src[at(b)];
          count++;
        }
      }
      for (var b = 0; b < out; b++) {
        final add = b + r, drop = b - r - 1;
        if (add < out && src[at(add)] >= 0) {
          sum += src[at(add)];
          count++;
        }
        if (drop >= 0 && src[at(drop)] >= 0) {
          sum -= src[at(drop)];
          count--;
        }
        if (src[at(b)] >= 0 && count > 0) dst[at(b)] = sum / count;
      }
    }
    return dst;
  }

  return pass(pass(v, true), false);
}

Iterable<int> _neighbours(int i) sync* {
  final x = i % out, y = i ~/ out;
  if (x > 0) yield i - 1;
  if (x < out - 1) yield i + 1;
  if (y > 0) yield i - out;
  if (y < out - 1) yield i + out;
}

double _dc(int i, double c) => sqrt(pow(i % out - c, 2) + pow(i ~/ out - c, 2));

/// Distances along the piece from [start], with straight steps (5) and
/// diagonal steps (7 ≈ 5·√2), so the pen front is round, not blocky.
Map<int, double> _sweep(int start, List<int> label, int id) {
  final dist = <int, int>{start: 0};
  final buckets = <List<int>>[
    [start],
  ];
  for (var d = 0; d < buckets.length; d++) {
    for (var k = 0; k < buckets[d].length; k++) {
      final j = buckets[d][k];
      if (dist[j] != d) continue;
      final x = j % out, y = j ~/ out;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= out || ny >= out) continue;
          final n = ny * out + nx;
          if (label[n] != id) continue;
          final nd = d + (dx != 0 && dy != 0 ? 7 : 5);
          final old = dist[n];
          if (old != null && old <= nd) continue;
          dist[n] = nd;
          while (buckets.length <= nd) {
            buckets.add([]);
          }
          buckets[nd].add(n);
        }
      }
    }
  }
  return dist.map((k, v) => MapEntry(k, v / 5));
}

// ---------------------------------------------------------------- preview

/// Original (enlarged) | new logo | new over original (red = only original,
/// = mismatch) | drawing at 40%.
void _preview(img.Image raw, img.Image lines, img.Image order, String path, (double, double, int) box) {
  const cell = 600;
  final (x0, y0, side) = box;
  final sheet = img.Image(width: cell * 4, height: cell, numChannels: 4);
  img.fill(sheet, color: img.ColorRgba8(255, 255, 255, 255));
  for (var y = 0; y < cell; y++) {
    for (var x = 0; x < cell; x++) {
      final r = raw.getPixelInterpolate(x0 + (x + 0.5) * side / cell - 0.5, y0 + (y + 0.5) * side / cell - 0.5);
      sheet.setPixelRgba(x, y, r.r, r.g, r.b, 255);
      final l = lines.getPixel(x * 2, y * 2);
      final a = l.a / 255;
      int mix(num c) => (255 * (1 - a) + c * a).round();
      sheet.setPixelRgba(cell + x, y, mix(l.r), mix(l.g), mix(l.b), 255);
      final inRef = min(r.r, min(r.g, r.b)) < 128;
      final inNew = a >= 0.5;
      final c = inRef && inNew
          ? img.ColorRgba8(150, 150, 150, 255)
          : inRef
              ? img.ColorRgba8(230, 0, 0, 255)
              : inNew
                  ? img.ColorRgba8(0, 0, 230, 255)
                  : img.ColorRgba8(255, 255, 255, 255);
      sheet.setPixel(cell * 2 + x, y, c);
      final o = order.getPixel(x, y);
      if (o.a > 0 && o.r + o.g / 256 >= 255 * 0.6 && a > 0) sheet.setPixelRgba(cell * 3 + x, y, mix(l.r), mix(l.g), mix(l.b), 255);
    }
  }
  File(path).writeAsBytesSync(img.encodePng(sheet));
  stdout.writeln('wrote $path');
}
