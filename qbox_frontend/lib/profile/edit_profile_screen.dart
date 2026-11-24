import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../customer/page_models.dart' show CharLimit, oneLine;
import '../models/qbox_user.dart';
import '../onboarding_draft.dart';
import '../registration_options.dart';
import '../services/api_client.dart';
import '../services/app_services.dart';
import '../udhaar/udhaar_widgets.dart';
import 'add_role_screen.dart' show roleName;

/// Change one's own details in [role], or fill them in for a new role
/// ([adding]; asks for the PIN). Closes with the changed account.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({required this.user, required this.role, this.adding = false, super.key});

  final QboxUser user;
  final QboxRole role;
  final bool adding;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _Field {
  _Field(
    this.name,
    this.label,
    String value, {
    this.needed,
    this.max = 120,
    this.phone = false,
    this.email = false,
    this.lines = 1,
  }) : text = TextEditingController(text: value);

  /// As the server calls it.
  final String name;
  final String label;

  /// What to say when it is empty; null = it may be.
  final String? needed;
  final int max;
  final bool phone;
  final bool email;
  final int lines;
  final TextEditingController text;

  String get value => oneLine(text.text);

  String? get problem {
    if (value.isEmpty) return needed;
    if (phone && !RegExp(r'^[6-9][0-9]{9}$').hasMatch(value)) return 'Enter a 10-digit mobile number';
    if (email && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) return 'Enter a valid email';
    return null;
  }
}

class _Choice {
  _Choice(this.name, this.label, this.value, List<String> options, String detail, this.needed)
    : options = [...options, if (value.isNotEmpty && !options.contains(value)) value],
      detail = _Field('${name}Detail', '$label (your own)', detail, needed: needed);

  final String name;
  final String label;
  final List<String> options;

  /// Typed when "Other" is chosen.
  final _Field detail;
  final String needed;
  String value;

  bool get other => value == otherOption;
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  /// [_Field]s and [_Choice]s, in order.
  late final List<Object> _parts = _build();
  bool _tried = false;
  bool _busy = false;

  List<Object> _build() {
    final shop = widget.user.shop;
    final customer = widget.user.customer;
    final supplier = widget.user.supplier;
    final phone = widget.adding ? widget.user.mobile : '';
    return switch (widget.role) {
      QboxRole.business => [
        _Field('shopName', 'Shop name', shop?.shopName ?? '', needed: 'Enter shop name'),
        _Choice(
          'businessType',
          'Business type',
          shop?.businessType ?? '',
          businessTypes,
          shop?.businessTypeDetail ?? '',
          'Enter your business type',
        ),
        _Choice(
          'shopCategory',
          'Shop category',
          shop?.shopCategory ?? '',
          shopCategories,
          shop?.shopCategoryDetail ?? '',
          'Enter your shop category',
        ),
        _Field('address', 'Shop address', shop?.address ?? '', needed: 'Enter shop address', max: 300, lines: 3),
        _Field(
          'contactNumber',
          'Contact number (customers can call it)',
          shop?.contactNumber ?? phone,
          needed: 'Enter a 10-digit mobile number',
          phone: true,
        ),
      ],
      QboxRole.customer => [
        _Field('fullName', 'Full name', customer?.fullName ?? '', needed: 'Enter your name'),
        _Field('email', 'Email (optional)', customer?.email ?? '', max: 160, email: true),
        _Field('address', 'Address (optional)', customer?.address ?? '', max: 300, lines: 3),
      ],
      QboxRole.supplier => [
        _Field('supplierName', 'Supplier name', supplier?.supplierName ?? '', needed: 'Enter supplier name'),
        _Choice(
          'businessType',
          'Business type',
          supplier?.businessType ?? '',
          businessTypes,
          supplier?.businessTypeDetail ?? '',
          'Enter your business type',
        ),
        _Field(
          'productsSupplied',
          'Products supplied',
          supplier?.productsSupplied ?? '',
          needed: 'Enter products supplied',
          max: 300,
          lines: 2,
        ),
        _Field(
          'contactNumber',
          'Contact number',
          supplier?.contactNumber ?? phone,
          needed: 'Enter a 10-digit mobile number',
          phone: true,
        ),
        _Field('address', 'Address', supplier?.address ?? '', needed: 'Enter address', max: 300, lines: 3),
      ],
    };
  }

  Iterable<_Field> get _fields sync* {
    for (final p in _parts) {
      if (p is _Field) yield p;
      if (p is _Choice && p.other) yield p.detail;
    }
  }

  @override
  void dispose() {
    for (final p in _parts) {
      (p is _Field ? p : (p as _Choice).detail).text.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _details => {
    for (final p in _parts)
      if (p is _Choice) p.name: p.value,
    for (final f in _fields) f.name: f.value,
  };

  Future<void> _add() async {
    final profile = ServicesScope.of(context).profile;
    final details = {..._details, if (widget.role == QboxRole.customer) 'mobileNumber': widget.user.mobile};
    final user = await showDialog<QboxUser>(
      context: context,
      builder: (_) => _PinDialog((pin) => profile.addRole(widget.role, pin, details)),
    );
    if (user != null && mounted) Navigator.of(context).pop(user);
  }

  Future<void> _save() async {
    setState(() => _tried = true);
    if (_fields.any((f) => f.problem != null) || _parts.any((p) => p is _Choice && p.value.isEmpty)) return;
    FocusScope.of(context).unfocus();
    if (widget.adding) return _add();
    setState(() => _busy = true);
    try {
      final user = await ServicesScope.of(context).profile.edit(widget.role, _details);
      if (mounted) Navigator.of(context).pop(user);
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.isNetwork ? 'This needs internet. Please try again.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: widget.adding ? 'Add ${roleName(widget.role)}' : 'Edit details', busy: _busy),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: UdCard(
                  child: Column(
                    children: [
                      for (final p in _parts) ...[
                        if (p is _Field) _text(p),
                        if (p is _Choice) ...[_choice(p), if (p.other) _text(p.detail)],
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  key: const Key('profile-save'),
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: udPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: udText(17, weight: FontWeight.w700),
                  ),
                  child: Text(widget.adding ? 'Continue' : 'Save'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _text(_Field f) => TextField(
    key: Key('profile-${f.name}'),
    controller: f.text,
    minLines: 1,
    maxLines: f.lines,
    keyboardType: f.phone
        ? TextInputType.phone
        : f.email
        ? TextInputType.emailAddress
        : TextInputType.text,
    textCapitalization: f.phone || f.email ? TextCapitalization.none : TextCapitalization.words,
    inputFormatters: [
      if (f.phone) ...[FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
      CharLimit(f.max),
    ],
    style: udText(15),
    onChanged: _tried ? (_) => setState(() {}) : null,
    decoration: InputDecoration(labelText: f.label, errorText: _tried ? f.problem : null),
  );

  Widget _choice(_Choice c) => DropdownButtonFormField<String>(
    key: Key('profile-${c.name}'),
    initialValue: c.value.isEmpty ? null : c.value,
    isExpanded: true,
    style: udText(15),
    decoration: InputDecoration(labelText: c.label, errorText: _tried && c.value.isEmpty ? 'Please choose one' : null),
    items: [
      for (final o in c.options)
        DropdownMenuItem(
          value: o,
          child: Text(o, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (v) => setState(() => c.value = v ?? ''),
  );
}

/// Asks for the PIN and tries [action] with it. Closes with its answer.
class _PinDialog extends StatefulWidget {
  const _PinDialog(this.action);

  final Future<QboxUser> Function(String pin) action;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _try() async {
    if (_busy) return;
    if (_pin.text.length != 4) {
      setState(() => _error = 'Enter your 4-digit PIN');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await widget.action(_pin.text);
      if (mounted) Navigator.of(context).pop(user);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.isNetwork ? 'This needs internet. Please try again.' : e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Enter your PIN'),
      content: TextField(
        key: const Key('role-pin'),
        controller: _pin,
        autofocus: true,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
        style: udText(22, weight: FontWeight.w700),
        decoration: InputDecoration(helperText: 'The PIN you log in with', errorText: _error, errorMaxLines: 4),
        onSubmitted: (_) => _try(),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('role-pin-ok'),
          onPressed: _busy ? null : _try,
          style: FilledButton.styleFrom(backgroundColor: udPurple),
          child: const Text('Add role'),
        ),
      ],
    );
  }
}
