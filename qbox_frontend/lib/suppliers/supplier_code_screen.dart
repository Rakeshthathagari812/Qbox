import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../udhaar/udhaar_models.dart' show rupees;
import '../udhaar/udhaar_widgets.dart';
import 'supplier_models.dart';

/// Connecting by a code: it goes to the supplier's phone with what the shop
/// owes; the supplier reads it out; the shop types it. Closes with the supplier.
class SupplierCodeScreen extends StatefulWidget {
  const SupplierCodeScreen({
    required this.name,
    required this.mobile,
    required this.send,
    required this.confirm,
    super.key,
  });

  final String name;
  final String mobile;
  final Future<SupplierCode> Function() send;
  final Future<Supplier> Function(String code) confirm;

  @override
  State<SupplierCodeScreen> createState() => _SupplierCodeScreenState();
}

class _SupplierCodeScreenState extends State<SupplierCodeScreen> {
  final _code = TextEditingController();
  SupplierCode? _sent;
  String? _error;
  bool _busy = false;
  int _resendIn = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _send();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  static String _message(ApiException e) => e.isNetwork ? 'This needs internet. Please try again.' : e.message;

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sent = await widget.send();
      if (!mounted) return;
      setState(() {
        _sent = sent;
        _code.clear();
        _resendIn = sent.resendInSeconds;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || _resendIn <= 1) t.cancel();
        if (mounted) setState(() => _resendIn = _resendIn <= 1 ? 0 : _resendIn - 1);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_code.text.length != 6) {
      setState(() => _error = 'Enter the 6-digit code they received');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final supplier = await widget.confirm(_code.text);
      if (mounted) Navigator.of(context).pop(supplier);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sent = _sent;
    final owed = sent?.balancePaise ?? 0;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'Connect', subtitle: widget.name, busy: _busy),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    UdCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sent == null ? 'Sending a code to' : 'Code sent to', style: udText(13, color: udBody)),
                          Text('${widget.name}, +91 ${widget.mobile}', style: udText(16, weight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('code'),
                            controller: _code,
                            autofocus: true,
                            enabled: sent != null,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            style: udText(28, weight: FontWeight.w800, color: udPurple).copyWith(letterSpacing: 10),
                            decoration: const InputDecoration(hintText: '······'),
                            onSubmitted: (_) => _confirm(),
                          ),
                          if (sent?.devOtp != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Test mode code: ${sent!.devOtp}',
                                key: const Key('code-dev'),
                                style: udText(12, color: udBody),
                              ),
                            ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              key: const Key('code-resend'),
                              onPressed: _busy || _resendIn > 0 ? null : _send,
                              child: Text(_resendIn > 0 ? 'Resend in ${_resendIn}s' : 'Resend code'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (sent != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: udSoft, borderRadius: BorderRadius.circular(14)),
                        child: Text(
                          '${owed >= 0 ? 'The message tells them you owe ${rupees(owed)} now.' : 'The message tells them you paid ${rupees(owed)} in advance.'} '
                          'Ask them to read out the code if that is right. It becomes the opening balance you both agree on.',
                          key: const Key('code-amount'),
                          style: udText(13),
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          key: const Key('code-error'),
                          style: udText(13, weight: FontWeight.w600, color: udDue),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  key: const Key('code-confirm'),
                  onPressed: _busy || sent == null ? null : _confirm,
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('Connect'),
                  style: FilledButton.styleFrom(
                    backgroundColor: udPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: udText(16, weight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
