import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../onboarding_draft.dart';
import '../services/api_client.dart';
import '../services/app_services.dart';
import '../udhaar/udhaar_models.dart' show rupees;
import '../udhaar/udhaar_widgets.dart';
import 'log_out.dart';
import 'profile_api.dart';

/// Deletes the whole account (all roles). Says what goes, what stays and what is
/// still owed; needs a tick and the PIN.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  AppServices? _services;
  final _pin = TextEditingController();
  DeleteCheck? _check;
  int _unsent = 0;
  bool _sure = false;
  bool _busy = false;
  String? _loadError;
  String? _error;

  AppServices get _app => _services!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    _load();
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  static String _words(ApiException e) => e.isNetwork ? 'This needs internet. Please try again.' : e.message;

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final unsent = await _app.unsentCount();
      final check = await _app.profile.deleteCheck();
      if (mounted) {
        setState(() {
          _unsent = unsent;
          _check = check;
          _loadError = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = _words(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_pin.text.length != 4) {
      setState(() => _error = 'Enter your 4-digit PIN');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _app.profile.deleteAccount(_pin.text);
      if (mounted) await leaveAccount(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _words(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final check = _check;
    final roles = OnboardingScope.of(context).user?.roles ?? const <QboxRole>{};
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'Delete my account', busy: _busy),
            if (_loadError != null)
              UdBanner(
                key: const Key('delete-load-error'),
                icon: Icons.wifi_off_rounded,
                text: _loadError!,
                actionLabel: 'Retry',
                onAction: _busy ? null : _load,
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (check != null) ..._warnings(check),
                    _card('Deleted at once', udDue, [
                      'Your details, photos and PIN',
                      'Calendar, notes, lists and expenses',
                      if (roles.contains(QboxRole.business)) 'Stock, supplier list, UPI ID and payment settings',
                      if (roles.contains(QboxRole.supplier)) 'Products, stock count and UPI ID',
                      if (roles.length > 1) 'All your roles, not only this one',
                    ]),
                    const SizedBox(height: 12),
                    _card('Kept, because it is also someone else\'s record', udBody, [
                      if (roles.contains(QboxRole.business))
                        'Your shop name and your customers\' udhaar lines, so they can still see them',
                      if (roles.contains(QboxRole.customer)) 'What shops wrote about you in their own udhaar books',
                      'Payments, and what a shop and a supplier shared',
                    ]),
                    const SizedBox(height: 12),
                    Text(
                      'Deleting does not cancel what you owe or are owed. Your number can sign up again as a new, empty account.',
                      style: udText(13, color: udBody),
                    ),
                    if (check != null && !check.paymentsOpen) ...[
                      const SizedBox(height: 8),
                      Material(
                        type: MaterialType.transparency,
                        child: CheckboxListTile(
                          key: const Key('delete-sure'),
                          value: _sure,
                          onChanged: _busy ? null : (v) => setState(() => _sure = v ?? false),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: udDue,
                          title: Text('I understand. This cannot be undone.', style: udText(14, weight: FontWeight.w600)),
                        ),
                      ),
                      if (_sure)
                        TextField(
                          key: const Key('delete-pin'),
                          controller: _pin,
                          enabled: !_busy,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                          style: udText(22, weight: FontWeight.w700),
                          decoration: InputDecoration(
                            labelText: 'Your PIN',
                            errorText: _error,
                            errorMaxLines: 4,
                          ),
                        ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 54,
                        child: FilledButton(
                          key: const Key('delete-account'),
                          onPressed: _sure && !_busy ? _delete : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: udDue,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            textStyle: udText(16, weight: FontWeight.w700),
                          ),
                          child: const Text('Delete my account'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _warnings(DeleteCheck c) => [
    for (final (key, text) in [
      if (c.paymentsOpen) ('delete-open', 'A payment to your shop is not finished. Answer it in Payments first.'),
      if (c.youOwePaise > 0) ('delete-owe', 'You still owe ${rupees(c.youOwePaise)}.'),
      if (c.owedToYouPaise > 0)
        ('delete-owed', '${rupees(c.owedToYouPaise)} is still owed to you. You will not see this list again.'),
      if (_unsent > 0) ('delete-unsent', '$_unsent changes on this phone are not sent yet. They will be lost.'),
    ])
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: UdCard(
          key: Key(key),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: udWarn),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: udText(14, weight: FontWeight.w600))),
            ],
          ),
        ),
      ),
  ];

  Widget _card(String title, Color color, List<String> lines) => UdCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: udText(15, weight: FontWeight.w700, color: color)),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: udText(14, color: udBody)),
                Expanded(child: Text(l, style: udText(14))),
              ],
            ),
          ),
      ],
    ),
  );
}
