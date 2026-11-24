import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../udhaar/udhaar_widgets.dart';
import 'profile_api.dart';

/// Takes or chooses a picture. Tests use a pretend one.
abstract class PhotoPicker {
  /// Null = chose nothing. Throws [PhotoException] if the phone refused.
  Future<Uint8List?> pick({required bool camera});
}

class PhotoException implements Exception {
  const PhotoException(this.message);

  final String message;
}

class PhonePhotoPicker implements PhotoPicker {
  final _picker = ImagePicker();

  @override
  Future<Uint8List?> pick({required bool camera}) async {
    final XFile? picture;
    try {
      picture = await _picker.pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        preferredCameraDevice: CameraDevice.front,
        requestFullMetadata: false,
      );
    } catch (_) {
      throw PhotoException(
        camera ? 'Allow camera access for QBOX in phone settings.' : 'Could not open the gallery. Please try again.',
      );
    }
    if (picture == null) return null;
    try {
      return await picture.readAsBytes();
    } finally {
      try {
        await File(picture.path).delete(); // the chooser's temporary copy
      } catch (_) {
        // Already gone.
      }
    }
  }
}

/// Photos already seen, kept on the phone. Cleared on log out.
abstract class PhotoStore {
  Future<Uint8List?> load(String ref);

  Future<void> save(String ref, Uint8List jpeg);

  Future<void> clear();
}

class SecurePhotoStore implements PhotoStore {
  static const _prefix = 'qbox_photo_';
  static const _max = 40;
  static const _storage = FlutterSecureStorage();

  @override
  Future<Uint8List?> load(String ref) async {
    try {
      final text = await _storage.read(key: '$_prefix$ref');
      return text == null ? null : base64Decode(text);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(String ref, Uint8List jpeg) async {
    try {
      final keys = (await _storage.readAll()).keys.where((k) => k.startsWith(_prefix)).toList();
      if (keys.length >= _max) await clear(); // they are loaded again when needed
      await _storage.write(key: '$_prefix$ref', value: base64Encode(jpeg));
    } catch (_) {
      // It is loaded from the server next time.
    }
  }

  @override
  Future<void> clear() async {
    try {
      final keys = (await _storage.readAll()).keys.where((k) => k.startsWith(_prefix)).toList();
      for (final key in keys) {
        await _storage.delete(key: key);
      }
    } catch (_) {
      // Storage unreadable: nothing that can be read is left.
    }
  }
}

/// In memory only. Used by tests.
class MemoryPhotoStore implements PhotoStore {
  final Map<String, Uint8List> saved = {};

  @override
  Future<Uint8List?> load(String ref) async => saved[ref];

  @override
  Future<void> save(String ref, Uint8List jpeg) async => saved[ref] = jpeg;

  @override
  Future<void> clear() async => saved.clear();
}

/// A photo never changes under its ref, so one already on the phone is enough.
class PhotoRepository {
  PhotoRepository(this.api, this.store);

  final ProfileApi api;
  final PhotoStore store;

  final Map<String, Uint8List> _seen = {};
  final Map<String, Future<Uint8List?>> _loading = {};
  int _user = 0;

  Uint8List? seen(String ref) => _seen[ref];

  /// Null = not available now (no internet, or removed).
  Future<Uint8List?> load(String ref) async {
    final seen = _seen[ref];
    if (seen != null) return seen;
    return _loading[ref] ??= _load(ref).whenComplete(() {
      _loading.remove(ref);
    });
  }

  Future<Uint8List?> _load(String ref) async {
    final user = _user;
    var jpeg = await store.load(ref);
    if (jpeg == null) {
      try {
        jpeg = await api.photo(ref);
      } on ApiException {
        return null;
      }
      if (user != _user) return null;
      await store.save(ref, jpeg);
    }
    if (user != _user) return null;
    return _seen[ref] = jpeg;
  }

  Future<void> keep(String ref, Uint8List jpeg) async {
    _seen[ref] = jpeg;
    await store.save(ref, jpeg);
  }

  Future<void> clear() async {
    _user++;
    _seen.clear();
    await store.clear();
  }
}

/// A round photo; [icon] while there is none.
class QboxPhoto extends StatefulWidget {
  const QboxPhoto({required this.photo, required this.icon, this.size = 40, super.key});

  /// Its ref; null = none.
  final String? photo;
  final IconData icon;
  final double size;

  @override
  State<QboxPhoto> createState() => _QboxPhotoState();
}

class _QboxPhotoState extends State<QboxPhoto> {
  Uint8List? _jpeg;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(QboxPhoto old) {
    super.didUpdateWidget(old);
    if (old.photo != widget.photo) _load();
  }

  Future<void> _load() async {
    final ref = widget.photo;
    final photos = ServicesScope.of(context).photos;
    _jpeg = ref == null ? null : photos.seen(ref);
    if (ref == null || _jpeg != null) return;
    final jpeg = await photos.load(ref);
    if (mounted && widget.photo == ref && jpeg != null) setState(() => _jpeg = jpeg);
  }

  @override
  Widget build(BuildContext context) {
    final jpeg = _jpeg;
    final icon = Icon(widget.icon, color: udPurple, size: widget.size * 0.55);
    return Container(
      width: widget.size,
      height: widget.size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: udSoft, shape: BoxShape.circle),
      child: jpeg == null
          ? icon
          : Image.memory(
              jpeg,
              key: Key('photo-${widget.photo}'),
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: (widget.size * MediaQuery.devicePixelRatioOf(context)).round(),
              errorBuilder: (_, _, _) => icon,
            ),
    );
  }
}
