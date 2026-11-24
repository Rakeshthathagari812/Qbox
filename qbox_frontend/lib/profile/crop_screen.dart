import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

import '../udhaar/udhaar_widgets.dart';

/// Move and zoom a picture into the circle. Closes with the part inside the
/// square as a new small JPEG: nothing else of the original file (like where
/// it was taken) goes with it.
class CropScreen extends StatefulWidget {
  const CropScreen({required this.picture, super.key});

  final Uint8List picture;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

/// The photo's side, in dots.
const photoSide = 512;
const photoMaxBytes = 300000;

class _CropScreenState extends State<CropScreen> {
  final _area = GlobalKey();
  final _move = TransformationController();
  ui.Image? _image;
  bool _bad = false;
  bool _busy = false;
  double _placedFor = 0;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      // The phone's own decoder: also turns the picture the right way up.
      final codec = await ui.instantiateImageCodec(widget.picture);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (_) {
      if (mounted) setState(() => _bad = true);
    }
  }

  @override
  void dispose() {
    _move.dispose();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _use() async {
    setState(() => _busy = true);
    try {
      final area = _area.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await area.toImage(pixelRatio: photoSide / area.size.width);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final jpeg = encodeJpeg(data!.buffer, image.width, image.height);
      image.dispose();
      if (mounted) Navigator.of(context).pop(jpeg);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        udNotify(context, 'This photo could not be used. Please choose another one.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final side = box.biggest.shortestSide;
                  return Center(
                    child: SizedBox.square(
                      dimension: side,
                      child: _bad
                          ? Center(
                              child: Text(
                                'This photo could not be read.\nPlease choose another one.',
                                key: const Key('crop-bad'),
                                textAlign: TextAlign.center,
                                style: udText(15, color: Colors.white),
                              ),
                            )
                          : image == null
                          ? const Center(child: CircularProgressIndicator(color: Colors.white))
                          : _cropper(image, side),
                    ),
                  );
                },
              ),
            ),
            if (image != null) Text('Move and pinch to fit', style: udText(13, color: Colors.white70)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('crop-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        minimumSize: const Size(0, 52),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const Key('crop-use'),
                      onPressed: image == null || _busy ? null : _use,
                      style: FilledButton.styleFrom(backgroundColor: udPurple, minimumSize: const Size(0, 52)),
                      child: const Text('Use photo'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cropper(ui.Image image, double side) {
    // The shorter side fills the square.
    final scale = side / (image.width < image.height ? image.width : image.height);
    final wide = image.width * scale;
    final high = image.height * scale;
    if (_placedFor != side) {
      _placedFor = side;
      // Start in the middle.
      _move.value = Matrix4.translationValues((side - wide) / 2, (side - high) / 2, 0);
    }
    return Stack(
      children: [
        RepaintBoundary(
          key: _area,
          child: ColoredBox(
            color: Colors.white,
            child: SizedBox.square(
              dimension: side,
              child: InteractiveViewer(
                transformationController: _move,
                constrained: false,
                minScale: 1,
                maxScale: 6,
                child: SizedBox(
                  width: wide,
                  height: high,
                  child: RawImage(image: image, fit: BoxFit.fill),
                ),
              ),
            ),
          ),
        ),
        const Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: _Circle())),
        ),
      ],
    );
  }
}

/// Darkens what is outside the circle.
class _Circle extends CustomPainter {
  const _Circle();

  @override
  void paint(Canvas canvas, Size size) {
    final all = Offset.zero & size;
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(all)
        ..addOval(all.deflate(2)),
      Paint()..color = const Color(0x99000000),
    );
    canvas.drawOval(
      all.deflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_Circle old) => false;
}

/// Small enough for the server.
Uint8List encodeJpeg(ByteBuffer rgba, int width, int height) {
  final image = img.Image.fromBytes(width: width, height: height, bytes: rgba, numChannels: 4);
  for (final quality in const [85, 70, 50]) {
    final jpeg = img.encodeJpg(image, quality: quality);
    if (jpeg.length <= photoMaxBytes) return jpeg;
  }
  return img.encodeJpg(image, quality: 30);
}
