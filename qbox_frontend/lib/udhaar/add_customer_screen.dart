import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import 'udhaar_models.dart';
import 'udhaar_widgets.dart';

/// Adds a customer in two steps, like a ride OTP:
///   1. name + mobile -> QBOX sends a code by SMS to the customer's phone
///   2. the customer reads the code out -> the shopkeeper types it -> added.
/// This proves the number is real, is theirs, and that they agree.
/// Pops with the new [UdhaarCustomer].
///
/// With [changeNumberOf], the same two steps move an existing customer (and
/// all their history) to a new number; the code goes to the new number.
class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({this.initialName = '', this.changeNumberOf, super.key});

  final String initialName;
  final UdhaarCustomer? changeNumberOf;

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  late final TextEditingController _name;
  final _mobile = TextEditingController();
  final _limit = TextEditingController();
  final _otp = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  String? _devOtp;
  int _resendIn = 0;
  Timer? _timer;

  UdhaarCustomer? get _existing => widget.changeNumberOf;
  bool get _changing => _existing != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _existing?.name ?? widget.initialName);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _name.dispose();
    _mobile.dispose();
    _limit.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _pickContact() async {
    final contact = await ServicesScope.of(context).device.pickContact();
    if (contact == null || !mounted) return;
    final mobile = normalizeMobile(contact.phone);
    setState(() {
      if (!_changing && contact.name.trim().isNotEmpty) _name.text = contact.name.trim();
      _mobile.text = mobile ?? '';
      _error = mobile == null
          ? 'This contact has no Indian mobile number. Type it below.'
          : null;
    });
  }

  String? _check() {
    if (_name.text.trim().isEmpty) return 'Enter customer name';
    if (!RegExp(r'^[6-9][0-9]{9}$').hasMatch(_mobile.text)) {
      return 'Enter a 10-digit mobile number';
    }
    if (_changing && _mobile.text == _existing!.mobile) {
      return 'This is already the customer\'s number';
    }
    if (!_changing && _limit.text.trim().isNotEmpty && parsePaise(_limit.text) == null) {
      return 'Enter the credit limit in rupees, or leave it empty';
    }
    return null;
  }

  Future<void> _sendCode() async {
    final problem = _check();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final udhaar = ServicesScope.of(context).udhaar;
      final sent = _changing
          ? await udhaar.sendNumberInvite(_existing!.id, _mobile.text)
          : await udhaar.sendInvite(_name.text.trim(), _mobile.text);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _devOtp = sent.devOtp;
        _otp.clear();
      });
      _startResendTimer(sent.resendInSeconds);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startResendTimer(int seconds) {
    _timer?.cancel();
    setState(() => _resendIn = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _resendIn <= 1) {
        t.cancel();
        if (mounted) setState(() => _resendIn = 0);
        return;
      }
      setState(() => _resendIn--);
    });
  }

  Future<void> _confirm() async {
    if (!RegExp(r'^[0-9]{6}$').hasMatch(_otp.text)) {
      setState(() => _error = 'Enter the 6-digit code the customer received');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final udhaar = ServicesScope.of(context).udhaar;
      final customer = _changing
          ? await udhaar.changeNumber(_existing!.id, _mobile.text, _otp.text)
          : await udhaar.addCustomer(
              name: _name.text.trim(),
              mobile: _mobile.text,
              otp: _otp.text,
              creditLimitPaise: _limit.text.trim().isEmpty ? null : parsePaise(_limit.text),
            );
      if (mounted) Navigator.of(context).pop(customer);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
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
            UdHeader(
              title: _changing ? 'Change number' : 'Add customer',
              subtitle: _codeSent
                  ? 'Step 2 of 2: enter the code'
                  : (_changing ? 'Step 1 of 2: the new number' : 'Step 1 of 2: customer details'),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: _codeSent ? _codeStep() : _detailsStep(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  key: Key(_codeSent ? 'add-confirm' : 'add-send-code'),
                  onPressed: _busy ? null : (_codeSent ? _confirm : _sendCode),
                  icon: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(_codeSent ? Icons.person_add_alt_1_rounded : Icons.sms_rounded),
                  label: Text(
                    _codeSent
                        ? (_changing ? 'Change number' : 'Add customer')
                        : (_changing ? 'Send code to new number' : 'Send code to customer'),
                  ),
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

  Widget _detailsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          key: const Key('add-pick-contact'),
          onPressed: _pickContact,
          icon: const Icon(Icons.contacts_rounded),
          label: const Text('Pick from phone contacts'),
          style: OutlinedButton.styleFrom(
            foregroundColor: udPurple,
            backgroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            side: const BorderSide(color: Color(0xFFD9CEF5)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: udText(15, weight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 12),
        UdCard(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            children: [
              if (_changing)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Old number: +91 ${_existing!.mobile}',
                    key: const Key('add-old-number'),
                    style: udText(13, color: udBody),
                  ),
                ),
              TextField(
                key: const Key('add-name'),
                controller: _name,
                enabled: !_changing,
                maxLength: 80,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Customer name', counterText: ''),
              ),
              TextField(
                key: const Key('add-mobile'),
                controller: _mobile,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: InputDecoration(
                  labelText: _changing ? 'New mobile number' : 'Mobile number',
                  prefixText: '+91 ',
                ),
              ),
              if (!_changing)
                TextField(
                key: const Key('add-limit'),
                controller: _limit,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: const InputDecoration(
                  labelText: 'Credit limit (optional)',
                  prefixText: '₹ ',
                  helperText: 'QBOX warns you when udhaar goes above this',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _info(
          Icons.verified_user_rounded,
          _changing
              ? 'QBOX will send an SMS code to the NEW number. When the customer tells you '
                    'the code, all their udhaar history moves to the new number.'
              : 'QBOX will send an SMS code to this number. Ask the customer to tell you '
                    'the code. This proves the number is theirs and that they agree.',
        ),
        _errorText(),
      ],
    );
  }

  Widget _codeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UdCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Code sent to', style: udText(13, color: udBody)),
              Text(
                '${_name.text.trim()} · +91 ${_mobile.text}',
                style: udText(16, weight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('add-otp'),
                controller: _otp,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: udText(28, weight: FontWeight.w800, color: udPurple).copyWith(letterSpacing: 10),
                decoration: const InputDecoration(hintText: '······'),
              ),
              if (_devOtp != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Test mode code: $_devOtp',
                    key: const Key('add-dev-otp'),
                    style: udText(12, color: udBody),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                children: [
                  TextButton(
                    key: const Key('add-change-number'),
                    onPressed: _busy ? null : () => setState(() {
                      _codeSent = false;
                      _error = null;
                    }),
                    child: const Text('Change number'),
                  ),
                  TextButton(
                    key: const Key('add-resend'),
                    onPressed: _busy || _resendIn > 0 ? null : _sendCode,
                    child: Text(_resendIn > 0 ? 'Resend in ${_resendIn}s' : 'Resend code'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _info(
          Icons.info_outline_rounded,
          'The customer must be at your shop. They should never share this code on a phone call.',
        ),
        _errorText(),
      ],
    );
  }

  Widget _info(IconData icon, String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: udSoft, borderRadius: BorderRadius.circular(14)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: udPurple, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: udText(12.5))),
      ],
    ),
  );

  Widget _errorText() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            _error!,
            key: const Key('add-error'),
            style: udText(13, weight: FontWeight.w600, color: udDue),
          ),
        );
}
