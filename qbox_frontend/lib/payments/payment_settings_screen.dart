import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../udhaar/udhaar_widgets.dart';
import 'payment_models.dart';

/// How the shop takes payments:
/// - its own UPI ID (free; the shop confirms each payment by hand), and/or
/// - its own Razorpay account (QBOX hears "₹250 received" by itself).
/// Money always goes straight to the shop's bank, never through QBOX.
class PaymentSettingsScreen extends StatefulWidget {
  const PaymentSettingsScreen({super.key});

  @override
  State<PaymentSettingsScreen> createState() => _PaymentSettingsScreenState();
}

class _PaymentSettingsScreenState extends State<PaymentSettingsScreen> {
  AppServices? _services;
  PaymentSettings? _settings;
  String? _error;
  bool _busy = false;
  bool _showSecret = false;
  final _upi = TextEditingController();
  final _upiName = TextEditingController();
  final _keyId = TextEditingController();
  final _keySecret = TextEditingController();

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
    _upi.dispose();
    _upiName.dispose();
    _keyId.dispose();
    _keySecret.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _apply(await _app.payments.settings());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isNetwork ? 'Payment settings need internet.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _apply(PaymentSettings settings) {
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _upi.text = settings.upiId ?? '';
      _upiName.text = settings.upiName ?? (settings.hasUpi ? '' : shopNameOf(context));
    });
  }

  Future<void> _run(Future<PaymentSettings> Function() action, String done) async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      _apply(await action());
      if (mounted) udNotify(context, done);
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.isNetwork ? 'This needs internet. Please try again.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveUpi() => _run(
    () => _app.payments.saveUpi(_upi.text.trim(), _upiName.text.trim()),
    _upi.text.trim().isEmpty ? 'UPI ID removed' : 'UPI ID saved',
  );

  Future<void> _connect() async {
    final keyId = _keyId.text.trim();
    final secret = _keySecret.text.trim();
    if (keyId.isEmpty || secret.isEmpty) {
      udNotify(context, 'Enter both the Key ID and the Key Secret');
      return;
    }
    await _run(() => _app.payments.connectRazorpay(keyId, secret), 'Razorpay connected');
    if (_settings?.razorpayConnected == true) {
      _keyId.clear();
      _keySecret.clear();
    }
  }

  Future<void> _disconnect() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Razorpay?'),
        content: const Text('QBOX will stop confirming payments by itself. Your Razorpay account is not changed.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('settings-disconnect-yes'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: udDue),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (sure == true && mounted) await _run(_app.payments.disconnectRazorpay, 'Razorpay disconnected');
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'Payment settings', subtitle: 'Money goes straight to your bank', busy: _busy),
            if (_error != null)
              UdBanner(icon: Icons.wifi_off_rounded, text: _error!, actionLabel: 'Retry', onAction: _load),
            Expanded(
              child: s == null
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        _razorpayCard(s),
                        const SizedBox(height: 12),
                        _upiCard(s),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _razorpayCard(PaymentSettings s) {
    final String status;
    final Color color;
    if (s.razorpayConnected) {
      status = 'Connected: ${s.razorpayKeyHint ?? ''}${s.testMode ? ' (test mode)' : ''}';
      color = udPaid;
    } else if (s.usingTestAccount) {
      status = 'Using the QBOX test account (pretend money). Connect your own for real payments.';
      color = udWarn;
    } else {
      status = 'Not connected';
      color = udBody;
    }
    return UdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: udPurple),
              const SizedBox(width: 8),
              Expanded(child: Text('Automatic payments (Razorpay)', style: udText(16, weight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'QBOX hears "₹250 received" by itself, and udhaar updates by itself. '
            'Razorpay takes a small fee on each payment.',
            style: udText(13, color: udBody),
          ),
          const SizedBox(height: 8),
          Text(status, key: const Key('settings-razorpay-status'), style: udText(13, weight: FontWeight.w600, color: color)),
          const SizedBox(height: 12),
          if (s.razorpayConnected)
            OutlinedButton.icon(
              key: const Key('settings-disconnect'),
              onPressed: _busy ? null : _disconnect,
              icon: const Icon(Icons.link_off_rounded),
              label: const Text('Disconnect'),
              style: OutlinedButton.styleFrom(foregroundColor: udDue),
            )
          else ...[
            Text(
              'In the Razorpay dashboard: Account & Settings > API Keys > Generate Key. '
              'Type the two values here. Never share them with anyone.',
              style: udText(12, color: udBody),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('settings-key-id'),
              controller: _keyId,
              autocorrect: false,
              enableSuggestions: false,
              decoration: _field('Key ID (rzp_test_… or rzp_live_…)'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('settings-key-secret'),
              controller: _keySecret,
              obscureText: !_showSecret,
              autocorrect: false,
              enableSuggestions: false,
              decoration: _field('Key Secret').copyWith(
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _showSecret = !_showSecret),
                  icon: Icon(_showSecret ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                ),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('settings-connect'),
              onPressed: _busy ? null : _connect,
              icon: const Icon(Icons.link_rounded),
              label: const Text('Connect Razorpay'),
              style: FilledButton.styleFrom(backgroundColor: udPurple),
            ),
          ],
        ],
      ),
    );
  }

  Widget _upiCard(PaymentSettings s) {
    return UdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, color: udPurple),
              const SizedBox(width: 8),
              Expanded(child: Text('Your own UPI ID', style: udText(16, weight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Free. Customers scan a QR with the amount filled in. '
            'You check your UPI app and tap "Money received" yourself.',
            style: udText(13, color: udBody),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('settings-upi'),
            controller: _upi,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.emailAddress,
            decoration: _field('UPI ID, e.g. lakshmistores@okaxis'),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('settings-upi-name'),
            controller: _upiName,
            maxLength: 60,
            decoration: _field('Name shown in UPI apps').copyWith(counterText: ''),
          ),
          const SizedBox(height: 10),
          FilledButton(
            key: const Key('settings-upi-save'),
            onPressed: _busy ? null : _saveUpi,
            style: FilledButton.styleFrom(backgroundColor: udPurple),
            child: const Text('Save UPI ID'),
          ),
        ],
      ),
    );
  }

  InputDecoration _field(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: udSoft,
    isDense: true,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
  );
}
