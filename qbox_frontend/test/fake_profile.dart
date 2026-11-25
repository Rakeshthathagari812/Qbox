import 'dart:typed_data';

import 'package:qbox_app/models/qbox_user.dart';
import 'package:qbox_app/onboarding_draft.dart';
import 'package:qbox_app/profile/photos.dart';
import 'package:qbox_app/profile/profile_api.dart';
import 'package:qbox_app/services/api_client.dart';

/// Pretend profile server for one user.
class FakeProfileApi implements ProfileApi {
  QboxUser user = const QboxUser(
    id: 1,
    mobile: '9123456789',
    roles: {QboxRole.business, QboxRole.customer, QboxRole.supplier},
    shop: ShopProfile(
      qboxId: 'QBM10001',
      shopName: 'Sri Rama Kirana',
      businessType: 'Retail',
      shopCategory: 'Grocery & Daily Needs',
      address: 'Main Road',
      contactNumber: '9123456789',
    ),
    customer: CustomerProfile(qboxId: 'QBC10001', fullName: 'Ramu'),
    supplier: SupplierProfile(
      qboxId: 'QBS10001',
      supplierName: 'Sri Venkateswara Suppliers',
      businessType: 'Wholesale',
      productsSupplied: 'FMCG',
      contactNumber: '9123456789',
      address: 'Jeedimetla',
    ),
  );

  String pin = '4826';
  bool offline = false;
  final Map<String, Uint8List> photos = {};
  final List<String> calls = [];
  int _next = 1;

  void _check(String call) {
    calls.add(call);
    if (offline) {
      throw const ApiException('NETWORK', 'Cannot reach the QBOX server. Check your internet connection.');
    }
  }

  QboxUser _put(QboxRole role, Map<String, dynamic> changes) {
    final json = user.toJson();
    final name = switch (role) {
      QboxRole.business => 'shop',
      QboxRole.customer => 'customer',
      QboxRole.supplier => 'supplier',
    };
    json[name] = {...?json[name] as Map<String, dynamic>?, ...changes};
    return user = QboxUser.fromJson(json);
  }

  @override
  Future<QboxUser> edit(QboxRole role, Map<String, dynamic> details) async {
    _check('edit ${roleCode(role)}');
    return _put(role, details);
  }

  @override
  Future<QboxUser> addRole(QboxRole role, String given, Map<String, dynamic> details) async {
    _check('add ${roleCode(role)}');
    if (given != pin) throw const ApiException('WRONG_PIN', 'The PIN is not right', status: 400);
    user = QboxUser.fromJson({
      ...user.toJson(),
      'roles': [for (final r in QboxRole.values) if (r == role || user.roles.contains(r)) roleCode(r)],
    });
    return _put(role, {'qboxId': 'QB-NEW', ...details});
  }

  @override
  Future<QboxUser> setPhoto(QboxRole role, Uint8List jpeg) async {
    _check('set photo');
    final ref = 'photo${_next++}';
    photos[ref] = jpeg;
    return _put(role, {'photo': ref});
  }

  @override
  Future<QboxUser> removePhoto(QboxRole role) async {
    _check('remove photo');
    return _put(role, {'photo': null});
  }

  @override
  Future<Uint8List> photo(String ref) async {
    _check('photo $ref');
    return photos[ref] ?? (throw const ApiException('PHOTO_NOT_FOUND', 'This photo is not available', status: 404));
  }

  @override
  Future<String> changePin(String oldPin, String newPin) async {
    _check('pin');
    if (oldPin != pin) throw const ApiException('WRONG_PIN', 'The old PIN is not right', status: 400);
    if (newPin == '1234') {
      throw const ApiException('INVALID_INPUT', 'This PIN is too easy to guess. Choose a different PIN', status: 400);
    }
    pin = newPin;
    return 'new-token';
  }

  @override
  Future<void> logOutAll() async => _check('log out all');

  DeleteCheck toDelete = const DeleteCheck();
  SupportContact contact = const SupportContact();

  @override
  Future<DeleteCheck> deleteCheck() async {
    _check('delete check');
    return toDelete;
  }

  @override
  Future<void> deleteAccount(String given) async {
    _check('delete');
    if (given != pin) throw const ApiException('WRONG_PIN', 'The PIN is not right', status: 400);
  }

  @override
  Future<SupportContact> support() async {
    _check('support');
    return contact;
  }
}

/// Pretend camera and gallery.
class FakePhotoPicker implements PhotoPicker {
  Uint8List? next;
  PhotoException? error;
  final List<bool> cameras = [];

  @override
  Future<Uint8List?> pick({required bool camera}) async {
    cameras.add(camera);
    final problem = error;
    if (problem != null) throw problem;
    return next;
  }
}
