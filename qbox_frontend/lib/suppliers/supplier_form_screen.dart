import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../udhaar/udhaar_models.dart' show newClientRef, normalizeMobile;
import '../udhaar/udhaar_widgets.dart';
import 'supplier_code_screen.dart';
import 'supplier_models.dart';

/// Add a supplier, or change one ([supplier] given). When adding, a code the
/// supplier reads out connects the two at once (it can be skipped). Returns
/// the saved supplier.
class SupplierFormScreen extends StatefulWidget {
  const SupplierFormScreen({this.supplier, super.key});

  final Supplier? supplier;

  @override
  State<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends State<SupplierFormScreen> {
  late final _name = TextEditingController(text: widget.supplier?.name ?? '');
  late final _mobile = TextEditingController(text: widget.supplier?.mobile ?? '');
  late final _supplies = TextEditingController(text: widget.supplier?.supplies ?? '');
  late final _note = TextEditingController(text: widget.supplier?.note ?? '');
  final String _clientRef = newClientRef();
  String? _error;
  bool _saving = false;

  bool get _adding => widget.supplier == null;

  @override
  void dispose() {
    for (final c in [_name, _mobile, _supplies, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickContact() async {
    final contact = await ServicesScope.of(context).device.pickContact();
    if (contact == null || !mounted) return;
    final mobile = normalizeMobile(contact.phone);
    setState(() {
      if (_name.text.trim().isEmpty) _name.text = contact.name;
      if (mobile != null) {
        _mobile.text = mobile;
        _error = null;
      } else {
        _error = 'That contact has no Indian mobile number';
      }
    });
  }

  Future<void> _save({bool skipCode = false}) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = "Enter the supplier's name");
      return;
    }
    final mobileText = _mobile.text.trim();
    final mobile = mobileText.isEmpty ? null : normalizeMobile(mobileText);
    if (mobileText.isNotEmpty && mobile == null) {
      setState(() => _error = 'Enter a valid 10-digit mobile number');
      return;
    }
    if (_adding && mobile == null && !skipCode) {
      setState(() => _error = 'Enter their mobile number, or tap "Add without code"');
      return;
    }
    final repo = ServicesScope.of(context).suppliers;
    String? text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    Future<Supplier> add([String? otp]) => repo.addSupplier(
      name: name,
      mobile: mobile,
      supplies: text(_supplies),
      note: text(_note),
      otp: otp,
      clientRef: _clientRef,
    );
    if (_adding && !skipCode) {
      setState(() => _error = null);
      final saved = await Navigator.of(context).push<Supplier>(
        MaterialPageRoute(
          builder: (_) => SupplierCodeScreen(
            name: name,
            mobile: mobile!,
            send: () => repo.sendNewCode(name: name, mobile: mobile),
            confirm: add,
          ),
        ),
      );
      if (saved != null && mounted) Navigator.of(context).pop(saved);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = _adding
          ? await add()
          : await repo.changeSupplier(widget.supplier!.id, name: name, mobile: mobile, supplies: text(_supplies), note: text(_note));
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isNetwork ? 'Adding or changing suppliers needs internet.' : e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: _adding ? 'Add supplier' : 'Change supplier', busy: _saving),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  UdCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          key: const Key('supplier-name'),
                          controller: _name,
                          maxLength: 80,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(labelText: 'Supplier / company name', counterText: ''),
                        ),
                        TextField(
                          key: const Key('supplier-mobile'),
                          controller: _mobile,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: 'Mobile (for calls and WhatsApp orders)',
                            prefixText: '+91 ',
                            suffixIcon: IconButton(
                              key: const Key('supplier-contact'),
                              onPressed: _pickContact,
                              icon: const Icon(Icons.contacts_outlined),
                              tooltip: 'Pick from contacts',
                            ),
                          ),
                        ),
                        TextField(
                          key: const Key('supplier-supplies'),
                          controller: _supplies,
                          maxLength: 200,
                          decoration: const InputDecoration(labelText: 'What they supply, e.g. rice, dal, oil', counterText: ''),
                        ),
                        TextField(
                          key: const Key('supplier-note'),
                          controller: _note,
                          maxLength: 300,
                          decoration: const InputDecoration(labelText: 'Note (optional)', counterText: ''),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!, key: const Key('supplier-error'), style: udText(13, weight: FontWeight.w600, color: udDue)),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      key: const Key('supplier-save'),
                      onPressed: _saving ? null : () => _save(),
                      style: FilledButton.styleFrom(
                        backgroundColor: udPurple,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        textStyle: udText(16, weight: FontWeight.w700),
                      ),
                      child: Text(_adding ? 'Send code and connect' : 'Save'),
                    ),
                  ),
                  if (_adding) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      key: const Key('supplier-skip'),
                      onPressed: _saving ? null : () => _save(skipCode: true),
                      child: const Text('Add without code'),
                    ),
                    Text(
                      'The code goes to their phone. When they read it out, you are connected: you see their products, '
                      'and you both see one account.',
                      textAlign: TextAlign.center,
                      style: udText(12, color: udBody),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
