import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../translator/languages.dart';
import '../translator/voice_language.dart';
import '../udhaar/udhaar_models.dart';
import '../udhaar/udhaar_widgets.dart';
import 'collect_screen.dart';
import 'payment_models.dart';
import 'payment_settings_screen.dart';

/// Opens the shop's Payments screen (the "Payments" home tile).
Widget openPayments(BuildContext context) => const PaymentsScreen();

/// Everything received today, newest first. While open, it checks every few
/// seconds and says each new payment out loud ("₹750 received from Ramesh"),
/// including udhaar a customer paid from their own QBOX.
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({this.checkEvery = const Duration(seconds: 10), this.now, super.key});

  final Duration checkEvery;

  /// For tests: pretend it is this moment.
  final DateTime? now;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  AppServices? _services;
  PaymentsDay? _day;
  PaymentSettings? _settings;
  String? _error;
  bool _busy = false;
  bool _loading = false;
  Timer? _timer;
  AppLanguage _voiceLang = AppLanguage.english;

  /// Payments already shown; anything new gets announced.
  final Set<int> _known = {};
  bool _firstLoad = true;

  AppServices get _app => _services!;
  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final lang = await readVoiceLanguage(_app.settings);
    if (mounted) setState(() => _voiceLang = lang);
    await Future.wait([_loadSettings(), _refresh(showBusy: true)]);
    _timer = Timer.periodic(widget.checkEvery, (_) => _refresh());
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _app.payments.settings();
      if (mounted) setState(() => _settings = settings);
    } on ApiException {
      // Shown by the list's own error.
    }
  }

  Future<void> _refresh({bool showBusy = false, bool announce = true}) async {
    if (_loading) return;
    _loading = true;
    if (showBusy) setState(() => _busy = true);
    try {
      final day = await _app.payments.today();
      if (!mounted) return;
      final fresh = day.payments.where((p) => !_known.contains(p.id)).toList();
      _known.addAll(day.payments.map((p) => p.id));
      setState(() {
        _day = day;
        _error = null;
      });
      if (!_firstLoad && announce) {
        for (final p in fresh.reversed) {
          await _app.speaker.say(receivedWords(p.amountPaise, _voiceLang, from: p.customerName),
              locale: _voiceLang.voiceLocale);
        }
      }
      _firstLoad = false;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isNetwork ? 'Offline: cannot check payments right now.' : e.message);
    } finally {
      _loading = false;
      if (mounted && showBusy) setState(() => _busy = false);
    }
  }

  Future<void> _go(Widget screen) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    await _loadSettings();
    // What was collected on that screen was already announced there.
    await _refresh(announce: false);
  }

  @override
  Widget build(BuildContext context) {
    final day = _day;
    final settings = _settings;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(
              title: 'Payments',
              subtitle: 'Received today',
              busy: _busy,
              actions: [
                IconButton(
                  key: const Key('payments-settings'),
                  onPressed: () => _go(const PaymentSettingsScreen()),
                  icon: const Icon(Icons.settings_outlined, color: udPurple),
                  tooltip: 'Payment settings',
                ),
              ],
            ),
            if (_error != null)
              UdBanner(key: const Key('payments-error'), icon: Icons.wifi_off_rounded, text: _error!),
            if (settings != null && !settings.canCollect)
              UdBanner(
                key: const Key('payments-setup'),
                icon: Icons.info_outline_rounded,
                color: udPurple,
                background: udSoft,
                text: 'Add your UPI ID or connect Razorpay to start taking payments.',
                actionLabel: 'Set up',
                onAction: () => _go(const PaymentSettingsScreen()),
              ),
            if (settings?.testMode == true)
              const UdBanner(
                key: Key('payments-test-mode'),
                icon: Icons.science_outlined,
                color: udPurple,
                background: udSoft,
                text: 'Test mode: pretend money only.',
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    UdCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Received today', style: udText(13, color: udBody)),
                          Text(
                            rupees(day?.totalPaise ?? 0),
                            key: const Key('payments-total'),
                            style: udText(34, weight: FontWeight.w800, color: udPaid),
                          ),
                          Text(
                            (day?.payments.length ?? 0) == 1 ? '1 payment' : '${day?.payments.length ?? 0} payments',
                            style: udText(13, color: udBody),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (day != null && day.payments.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'No payments yet today.\nTap "Collect payment" to show a QR.',
                          key: const Key('payments-empty'),
                          textAlign: TextAlign.center,
                          style: udText(14, color: udBody),
                        ),
                      ),
                    for (final p in day?.payments ?? const <Payment>[]) _PaymentTile(payment: p, now: _now),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  key: const Key('payments-collect'),
                  onPressed: () => _go(const CollectScreen()),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: const Text('Collect payment'),
                  style: FilledButton.styleFrom(
                    backgroundColor: udPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: udText(17, weight: FontWeight.w700),
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

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment, required this.now});

  final Payment payment;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final icon = switch (payment.source) {
      PaymentSource.udhaar => Icons.menu_book_rounded,
      PaymentSource.manual => Icons.account_balance_wallet_outlined,
      PaymentSource.counter => Icons.qr_code_2_rounded,
    };
    final paidAt = payment.paidAt;
    return Container(
      key: Key('payment-${payment.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: udSoft, child: Icon(icon, color: udPurple)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(payment.payer ?? 'UPI payment', style: udText(14, weight: FontWeight.w700)),
                if ((payment.note ?? '').isNotEmpty)
                  Text(payment.note!, maxLines: 1, overflow: TextOverflow.ellipsis, style: udText(12, color: udBody)),
                Text(
                  '${payment.source.label}${paidAt == null ? '' : ' · ${whenLabel(paidAt, now)}'}',
                  style: udText(11, color: udBody),
                ),
              ],
            ),
          ),
          Text('+ ${rupees(payment.amountPaise)}', style: udText(16, weight: FontWeight.w700, color: udPaid)),
        ],
      ),
    );
  }
}
