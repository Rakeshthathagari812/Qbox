import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../udhaar/udhaar_widgets.dart';

/// The camera behind "Pay to Shop". Reading happens on the phone; nothing it
/// sees is kept or sent anywhere. Tests use a pretend one.
abstract class QrCamera {
  /// The live picture. The camera runs only while this is on screen.
  Widget view(void Function(String text) onText);

  /// Whether the light is on.
  ValueNotifier<bool> get torch;

  Future<void> toggleTorch();

  /// Lets the person choose a picture and reads the QR in it.
  /// Null = chose nothing; empty = no QR in the picture.
  Future<String?> readPicture();

  void dispose();
}

class PhoneQrCamera implements QrCamera {
  final _picker = ImagePicker();
  MobileScannerController? _controller;

  @override
  final torch = ValueNotifier(false);

  @override
  Widget view(void Function(String text) onText) => _CameraView(camera: this, onText: onText);

  @override
  Future<void> toggleTorch() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.toggleTorch();
    } catch (_) {
      // The camera was just closing.
    }
  }

  @override
  Future<String?> readPicture() async {
    // The phone's own picture chooser: QBOX gets only the one picture chosen.
    final picture = await _picker.pickImage(source: ImageSource.gallery);
    if (picture == null) return null;
    final reader = MobileScannerController(autoStart: false);
    try {
      final found = await reader.analyzeImage(picture.path, formats: const [BarcodeFormat.qrCode]);
      for (final code in found?.barcodes ?? const <Barcode>[]) {
        if ((code.rawValue ?? '').trim().isNotEmpty) return code.rawValue;
      }
      return '';
    } catch (_) {
      return '';
    } finally {
      unawaited(reader.dispose());
      try {
        await File(picture.path).delete(); // the chooser's temporary copy
      } catch (_) {
        // Already gone.
      }
    }
  }

  @override
  void dispose() => torch.dispose();
}

class _CameraView extends StatefulWidget {
  const _CameraView({required this.camera, required this.onText});

  final PhoneQrCamera camera;
  final void Function(String text) onText;

  @override
  State<_CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<_CameraView> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);

  @override
  void initState() {
    super.initState();
    widget.camera._controller = _controller;
    _controller.addListener(_onState);
  }

  void _onState() => widget.camera.torch.value = _controller.value.torchState == TorchState.on;

  @override
  void dispose() {
    _controller.removeListener(_onState);
    if (widget.camera._controller == _controller) widget.camera._controller = null;
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MobileScanner(
      controller: _controller,
      onDetect: (capture) {
        for (final code in capture.barcodes) {
          final text = code.rawValue;
          if (text != null) widget.onText(text);
        }
      },
      errorBuilder: (context, error) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(48),
            child: Text(
              error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? 'QBOX needs the camera to scan.\nTurn it on in phone Settings → Apps → QBOX → Permissions, '
                        'or use Upload QR or Number below.'
                  : 'The camera could not open. Use Upload QR or Number below.',
              key: const Key('scan-error'),
              textAlign: TextAlign.center,
              style: udText(14, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
