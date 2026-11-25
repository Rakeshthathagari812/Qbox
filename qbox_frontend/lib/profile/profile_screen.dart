import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/qbox_user.dart';
import '../onboarding_draft.dart';
import '../services/api_client.dart';
import '../services/app_services.dart';
import '../translator/languages.dart';
import '../translator/voice_language.dart';
import '../udhaar/udhaar_widgets.dart';
import 'add_role_screen.dart';
import 'change_pin_screen.dart';
import 'crop_screen.dart';
import 'delete_account_screen.dart';
import 'edit_profile_screen.dart';
import 'legal_screen.dart';
import 'log_out.dart';
import 'notices.dart';
import 'notices_screen.dart';
import 'photos.dart';

IconData roleIcon(QboxRole role) => switch (role) {
  QboxRole.business => Icons.storefront_rounded,
  QboxRole.customer => Icons.person_outline,
  QboxRole.supplier => Icons.local_shipping_outlined,
};

/// Photo, details and settings of one role.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({required this.role, super.key});

  final QboxRole role;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  AppServices? _services;
  AppLanguage _voiceLang = AppLanguage.english;
  bool _busy = false;

  AppServices get _app => _services!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    _start();
  }

  /// The latest details from the server (they may have been changed on another phone).
  Future<void> _start() async {
    final lang = await readVoiceLanguage(_app.settings);
    if (!mounted) return;
    setState(() => _voiceLang = lang);
    final token = await _app.session.readToken();
    if (token == null) return;
    try {
      await _changed(await _app.auth.me(token));
    } on ApiException {
      // The copy on the phone is shown.
    }
  }

  Future<void> _changed(QboxUser user) async {
    if (!mounted) return;
    OnboardingScope.read(context).applyUser(user);
    await _app.session.saveUser(user);
  }

  // ---------- photo ----------

  Future<void> _photoMenu(String? now) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('photo-camera'),
              leading: const Icon(Icons.photo_camera_outlined, color: udPurple),
              title: const Text('Take photo'),
              onTap: () => Navigator.of(context).pop('camera'),
            ),
            ListTile(
              key: const Key('photo-gallery'),
              leading: const Icon(Icons.photo_library_outlined, color: udPurple),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(context).pop('gallery'),
            ),
            if (now != null)
              ListTile(
                key: const Key('photo-remove'),
                leading: const Icon(Icons.delete_outline_rounded, color: udDue),
                title: const Text('Remove photo'),
                onTap: () => Navigator.of(context).pop('remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'remove') {
      await _run(() async => _changed(await _app.profile.removePhoto(widget.role)), 'Photo removed');
    } else {
      await _newPhoto(camera: choice == 'camera');
    }
  }

  Future<void> _newPhoto({required bool camera}) async {
    final Uint8List? picture;
    try {
      picture = await _app.photoPicker.pick(camera: camera);
    } on PhotoException catch (e) {
      if (mounted) udNotify(context, e.message);
      return;
    }
    if (picture == null || !mounted) return;
    final chosen = picture;
    final jpeg = await Navigator.of(
      context,
    ).push<Uint8List>(MaterialPageRoute(builder: (_) => CropScreen(picture: chosen)));
    if (jpeg == null || !mounted) return;
    await _run(() async {
      final user = await _app.profile.setPhoto(widget.role, jpeg);
      final ref = user.photoFor(widget.role);
      if (ref != null) await _app.photos.keep(ref, jpeg);
      await _changed(user);
    }, 'Photo saved');
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) udNotify(context, done);
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.isNetwork ? 'This needs internet. Please try again.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- settings ----------

  Future<void> _edit(QboxUser user) async {
    final changed = await Navigator.of(context).push<QboxUser>(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(user: user, role: widget.role),
      ),
    );
    if (changed == null) return;
    await _changed(changed);
    if (mounted) udNotify(context, 'Saved');
  }

  Future<void> _changePin() async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ChangePinScreen()));
    if (changed == true && mounted) udNotify(context, 'PIN changed');
  }

  Future<void> _pickLanguage() async {
    final picked = await pickVoiceLanguage(
      context,
      current: _voiceLang,
      settings: _app.settings,
      translator: _app.translator,
    );
    if (picked != null && mounted) setState(() => _voiceLang = picked);
  }

  Future<void> _logOutAll() async {
    final unsent = await _app.unsentCount();
    if (!mounted) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out from all phones?'),
        content: Text(
          'This phone too. You will need your PIN to log in again.'
          '${unsent == 0 ? '' : '\n\nChanges not sent yet ($unsent) will be lost.'}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('log-out-all-sure'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: udDue),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _app.profile.logOutAll();
      if (mounted) await leaveAccount(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      udNotify(context, e.isNetwork ? 'This needs internet. Please try again.' : e.message);
    }
  }

  // ---------- screen ----------

  @override
  Widget build(BuildContext context) {
    final user = OnboardingScope.of(context).user;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'Profile', busy: _busy),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (user != null) ...[_top(user), const SizedBox(height: 12), _details(user)],
                    const SizedBox(height: 20),
                    Text('Settings', style: udText(16, weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    _card([
                      _row('profile-pin', Icons.lock_outline_rounded, 'Change PIN', onTap: _changePin),
                      if (NoticeType.of(widget.role).isNotEmpty)
                        _row(
                          'profile-notices',
                          Icons.notifications_none_rounded,
                          'Notifications',
                          onTap: () => Navigator.of(
                            context,
                          ).push(MaterialPageRoute<void>(builder: (_) => NoticeSettingsScreen(role: widget.role))),
                        ),
                      _row(
                        'profile-language',
                        Icons.translate_rounded,
                        'Voice language',
                        value: _voiceLang.nativeName,
                        onTap: _pickLanguage,
                      ),
                    ]),
                    const SizedBox(height: 20),
                    Text('Help', style: udText(16, weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    _card([
                      _row(
                        'profile-help',
                        Icons.help_outline_rounded,
                        'Help',
                        onTap: () => openLegal(context, LegalPage.help),
                      ),
                      _row(
                        'profile-privacy',
                        Icons.privacy_tip_outlined,
                        'Privacy Policy',
                        onTap: () => openLegal(context, LegalPage.privacy),
                      ),
                      _row(
                        'profile-terms',
                        Icons.description_outlined,
                        'Terms of Use',
                        onTap: () => openLegal(context, LegalPage.terms),
                      ),
                    ]),
                    const SizedBox(height: 20),
                    Text('Account', style: udText(16, weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    _card([
                      if (user != null && canAddRole(user))
                        _row(
                          'profile-add-role',
                          Icons.add_circle_outline_rounded,
                          'Add a role',
                          onTap: () => addRole(context),
                        ),
                      _row(
                        'profile-switch-role',
                        Icons.swap_horiz_rounded,
                        'Switch role',
                        onTap: () => Navigator.of(context)
                          ..pop()
                          ..pop(),
                      ),
                      _row(
                        'profile-log-out-all',
                        Icons.phonelink_erase_rounded,
                        'Log out from all phones',
                        onTap: _busy ? null : _logOutAll,
                      ),
                      _row(
                        'profile-log-out',
                        Icons.logout_rounded,
                        'Log out',
                        color: udDue,
                        onTap: _busy ? null : () => logOut(context),
                      ),
                      _row(
                        'profile-delete',
                        Icons.delete_forever_outlined,
                        'Delete my account',
                        color: udDue,
                        onTap: _busy
                            ? null
                            : () => Navigator.of(
                                context,
                              ).push(MaterialPageRoute<void>(builder: (_) => const DeleteAccountScreen())),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _top(QboxUser user) {
    final photo = user.photoFor(widget.role);
    final id = user.qboxIdFor(widget.role) ?? '';
    return UdCard(
      child: Column(
        children: [
          Semantics(
            button: true,
            label: 'Change photo',
            child: GestureDetector(
              key: const Key('profile-photo'),
              onTap: _busy ? null : () => _photoMenu(photo),
              child: Stack(
                children: [
                  QboxPhoto(photo: photo, icon: roleIcon(widget.role), size: 104),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: udPurple,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            user.nameFor(widget.role),
            key: const Key('profile-name'),
            textAlign: TextAlign.center,
            style: udText(20, weight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          InkWell(
            key: const Key('profile-id'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: id));
              udNotify(context, 'QBOX ID copied');
            },
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text('QBOX ID: $id', style: udText(13, color: udBody)),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.copy_rounded, size: 15, color: udPurple),
                ],
              ),
            ),
          ),
          Text('Login number: +91 ${user.mobile}', style: udText(13, color: udBody)),
          const SizedBox(height: 6),
          Text(
            widget.role == QboxRole.business ? 'Your customers can see this photo.' : 'Only you can see this photo.',
            style: udText(12, color: udBody),
          ),
        ],
      ),
    );
  }

  Widget _details(QboxUser user) {
    final shop = user.shop;
    final customer = user.customer;
    final supplier = user.supplier;
    String own(String value, String detail) => detail.isEmpty ? value : detail;
    final lines = switch (widget.role) {
      QboxRole.business => [
        ('Business type', own(shop?.businessType ?? '', shop?.businessTypeDetail ?? '')),
        ('Category', own(shop?.shopCategory ?? '', shop?.shopCategoryDetail ?? '')),
        ('Address', shop?.address ?? ''),
        ('Contact number', shop?.contactNumber ?? ''),
      ],
      QboxRole.customer => [('Email', customer?.email ?? ''), ('Address', customer?.address ?? '')],
      QboxRole.supplier => [
        ('Business type', own(supplier?.businessType ?? '', supplier?.businessTypeDetail ?? '')),
        ('Products', supplier?.productsSupplied ?? ''),
        ('Contact number', supplier?.contactNumber ?? ''),
        ('Address', supplier?.address ?? ''),
      ],
    };
    return UdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Details', style: udText(16, weight: FontWeight.w700)),
              ),
              TextButton.icon(
                key: const Key('profile-edit'),
                onPressed: _busy ? null : () => _edit(user),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
                style: TextButton.styleFrom(foregroundColor: udPurple),
              ),
            ],
          ),
          for (final (label, value) in lines)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: udText(12, color: udBody)),
                  Text(value.isEmpty ? 'Not added' : value, style: udText(15, weight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> rows) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: Column(children: rows),
  );

  Widget _row(
    String key,
    IconData icon,
    String label, {
    String? value,
    Color color = udInk,
    required VoidCallback? onTap,
  }) => ListTile(
    key: Key(key),
    leading: Icon(icon, color: color == udInk ? udPurple : color),
    title: Text(
      label,
      style: udText(15, weight: FontWeight.w600, color: color),
    ),
    trailing: value == null
        ? const Icon(Icons.chevron_right_rounded, color: udBody)
        : Text(value, style: udText(14, color: udBody)),
    onTap: onTap,
  );
}
