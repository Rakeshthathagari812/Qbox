import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../calculator/voice_services.dart';
import '../services/api_client.dart';
import '../services/app_services.dart';
import '../translator/indic_numbers.dart';
import '../translator/languages.dart';
import '../translator/voice_language.dart';
import '../udhaar/udhaar_models.dart';
import '../udhaar/udhaar_widgets.dart';
import '../udhaar/voice_udhaar.dart' show digitsAmount;
import 'payment_models.dart';
import 'payment_settings_screen.dart';

/// Opens the Collect screen (the "QR & UPI" home tile).
Widget openCollect(BuildContext context) => const CollectScreen();

enum _Step { amount, waiting, manual, paid, ended }

/// Take a payment at the counter: say or type the amount, show a QR, and hear
/// "₹250 received" when it is paid.
///
/// - Razorpay set up: a one-time QR; Razorpay tells QBOX when it is paid.
/// - Only the shop's own UPI ID: a UPI QR with the amount; the shop taps
///   "Money received" after checking its UPI app.
class CollectScreen extends StatefulWidget {
  const CollectScreen({this.checkEvery = const Duration(seconds: 3), super.key});

  /// How often to ask whether the QR was paid.
  final Duration checkEvery;

  @override
  State<CollectScreen> createState() => _CollectScreenState();
}

class _CollectScreenState extends State<CollectScreen> {
  AppServices? _services;
  PaymentSettings? _settings;
  String? _settingsError;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  UdhaarCustomer? _customer;
  _Step _step = _Step.amount;
  Payment? _payment;
  int _paise = 0;
  String _clientRef = newClientRef();
  String _endedText = '';
  bool _busy = false;
  bool _listening = false;
  AppLanguage _voiceLang = AppLanguage.english;
  Timer? _timer;
  bool _checking = false;

  AppServices get _app => _services!;

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
    if (_listening) unawaited(_app.voice.stop());
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final lang = await readVoiceLanguage(_app.settings);
    if (mounted) setState(() => _voiceLang = lang);
    await _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _app.payments.settings();
      if (mounted) {
        setState(() {
          _settings = settings;
          _settingsError = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _settingsError = e.isNetwork ? 'Payments need internet.' : e.message);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const PaymentSettingsScreen()),
    );
    if (mounted) await _loadSettings();
  }

  Future<void> _pickVoiceLanguage() async {
    final picked = await pickVoiceLanguage(
      context,
      current: _voiceLang,
      settings: _app.settings,
      translator: _app.translator,
    );
    if (picked != null && mounted) setState(() => _voiceLang = picked);
  }

  /// "రెండు వందల యాభై" / "250" -> 25000 paise.
  Future<void> _speakAmount() async {
    if (_listening) {
      await _app.voice.stop();
      return;
    }
    setState(() => _listening = true);
    try {
      final words = await _app.voice.listen(localeId: _voiceLang.speechLocale, onWords: (_) {});
      if (!mounted) return;
      final paise = digitsAmount(numbersToDigits(words, _voiceLang));
      if (paise == null) {
        udNotify(context, words.trim().isEmpty
            ? 'Did not hear an amount. Tap Speak and say: 250'
            : 'Could not find one amount in "$words". Say just the amount, like 250');
        return;
      }
      _amount.text = paiseToText(paise);
    } on VoiceException catch (e) {
      if (mounted) udNotify(context, e.message);
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  Future<void> _pickCustomer() async {
    final book = await _app.udhaar.savedBook();
    if (!mounted) return;
    final customers = [...?book?.customers]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (customers.isEmpty) {
      udNotify(context, 'Your udhaar book is empty.');
      return;
    }
    final picked = await showModalBottomSheet<UdhaarCustomer>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in customers)
              ListTile(
                key: Key('collect-customer-${c.id}'),
                leading: UdAvatar(name: c.name, size: 36),
                title: Text(c.name, style: udText(15, weight: FontWeight.w600)),
                subtitle: Text(balanceLabel(c.balancePaise), style: udText(12, color: balanceColor(c.balancePaise))),
                onTap: () => Navigator.of(context).pop(c),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _customer = picked;
        if (_amount.text.trim().isEmpty && picked.balancePaise > 0) _amount.text = paiseToText(picked.balancePaise);
      });
    }
  }

  Future<void> _showQr() async {
    final settings = _settings;
    final paise = parsePaise(_amount.text);
    if (settings == null) return;
    if (paise == null || paise < 100) {
      udNotify(context, 'Enter an amount of at least ₹1');
      return;
    }
    FocusScope.of(context).unfocus();
    _paise = paise;
    if (!settings.automatic) {
      setState(() => _step = _Step.manual);
      return;
    }
    setState(() => _busy = true);
    try {
      final payment = await _app.payments.collect(
        amountPaise: paise,
        clientRef: _clientRef,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        udhaarCustomerId: _customer?.id,
      );
      if (!mounted) return;
      setState(() {
        _payment = payment;
        _step = _Step.waiting;
      });
      _timer?.cancel();
      _timer = Timer.periodic(widget.checkEvery, (_) => _check());
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.isNetwork ? 'Payments need internet. Please try again.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    final payment = _payment;
    if (payment == null || _checking || _step != _Step.waiting) return;
    _checking = true;
    try {
      final now = await _app.payments.payment(payment.id);
      if (!mounted || _step != _Step.waiting) return;
      _show(now);
    } on ApiException {
      // No internet for a moment: keep waiting and try again.
    } finally {
      _checking = false;
    }
  }

  void _show(Payment payment) {
    setState(() => _payment = payment);
    switch (payment.status) {
      case PaymentStatus.paid:
        _paid(payment);
      case PaymentStatus.expired:
        _end('This QR has expired. Make a new one.');
      case PaymentStatus.cancelled:
        _end('QR cancelled.');
      case PaymentStatus.waiting:
        break;
    }
  }

  void _paid(Payment payment) {
    _timer?.cancel();
    setState(() => _step = _Step.paid);
    HapticFeedback.heavyImpact();
    unawaited(_app.speaker.say(
      receivedWords(payment.amountPaise, _voiceLang, from: payment.customerName),
      locale: _voiceLang.voiceLocale,
    ));
  }

  void _end(String text) {
    _timer?.cancel();
    setState(() {
      _step = _Step.ended;
      _endedText = text;
    });
  }

  Future<void> _cancel() async {
    final payment = _payment;
    if (_step == _Step.manual || payment == null) {
      _again();
      return;
    }
    setState(() => _busy = true);
    try {
      _show(await _app.payments.cancel(payment.id));
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manualReceived() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Did ${rupees(_paise)} arrive?'),
        content: const Text('Check your UPI app or bank SMS first. Tap Yes only if the money is there.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Not yet')),
          FilledButton(
            key: const Key('collect-received-yes'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: udPaid),
            child: const Text('Yes, received'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final payment = await _app.payments.recordManual(
        amountPaise: _paise,
        clientRef: _clientRef,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        udhaarCustomerId: _customer?.id,
      );
      if (!mounted) return;
      _payment = payment;
      _paid(payment);
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.isNetwork ? 'This needs internet. Please try again.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _again() {
    _timer?.cancel();
    setState(() {
      _step = _Step.amount;
      _payment = null;
      _clientRef = newClientRef();
      _amount.clear();
      _note.clear();
      _customer = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(
              title: 'Collect payment',
              subtitle: settings == null
                  ? 'UPI QR'
                  : (settings.automatic ? 'UPI QR, confirmed by itself' : 'Your UPI QR'),
              busy: _busy,
              actions: [
                IconButton(
                  key: const Key('collect-settings'),
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings_outlined, color: udPurple),
                  tooltip: 'Payment settings',
                ),
              ],
            ),
            if (settings?.testMode == true)
              const UdBanner(
                key: Key('collect-test-mode'),
                icon: Icons.science_outlined,
                color: udPurple,
                background: udSoft,
                text: 'Test mode: pretend money only. No real money moves.',
              ),
            Expanded(child: _body(settings)),
          ],
        ),
      ),
    );
  }

  Widget _body(PaymentSettings? settings) {
    if (_settingsError != null && settings == null) {
      return _Message(
        icon: Icons.wifi_off_rounded,
        text: _settingsError!,
        button: 'Try again',
        buttonKey: const Key('collect-retry'),
        onPressed: _loadSettings,
      );
    }
    if (settings == null) return const Center(child: CircularProgressIndicator(color: udPurple));
    if (!settings.canCollect) {
      return _Message(
        icon: Icons.qr_code_2_rounded,
        text: 'Set up payments first: add your UPI ID, or connect Razorpay to hear "₹250 received" by itself.',
        button: 'Set up payments',
        buttonKey: const Key('collect-setup'),
        onPressed: _openSettings,
      );
    }
    return switch (_step) {
      _Step.amount => _amountStep(),
      _Step.waiting => _qrStep(automatic: true),
      _Step.manual => _qrStep(automatic: false),
      _Step.paid => _paidStep(),
      _Step.ended => _Message(
          icon: Icons.timer_off_outlined,
          text: _endedText,
          button: 'New QR',
          buttonKey: const Key('collect-again'),
          onPressed: _again,
        ),
    };
  }

  Widget _amountStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        UdCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Amount', style: udText(13, color: udBody)),
              TextField(
                key: const Key('collect-amount'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                style: udText(36, weight: FontWeight.w800),
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  prefixStyle: udText(36, weight: FontWeight.w800, color: udBody),
                  hintText: '0',
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _showQr(),
              ),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    key: const Key('collect-speak'),
                    onPressed: _speakAmount,
                    icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
                    label: Text(_listening ? 'Stop' : 'Speak amount'),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: VoiceLanguageChip(
                      key: const Key('collect-voice-lang'),
                      language: _voiceLang,
                      onPressed: _listening ? null : _pickVoiceLanguage,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        UdCard(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.menu_book_rounded, color: udPurple),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _customer == null ? 'For udhaar? (optional)' : 'Udhaar of ${_customer!.name}',
                  style: udText(14, weight: FontWeight.w600),
                ),
              ),
              if (_customer != null)
                IconButton(
                  key: const Key('collect-customer-clear'),
                  onPressed: () => setState(() => _customer = null),
                  icon: const Icon(Icons.close_rounded),
                ),
              TextButton(
                key: const Key('collect-customer'),
                onPressed: _pickCustomer,
                child: Text(_customer == null ? 'Choose' : 'Change'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('collect-note'),
          controller: _note,
          maxLength: 100,
          decoration: InputDecoration(
            hintText: 'Note (optional), e.g. rice 5 kg',
            filled: true,
            fillColor: Colors.white,
            counterText: '',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            key: const Key('collect-show-qr'),
            onPressed: _busy ? null : _showQr,
            icon: const Icon(Icons.qr_code_2_rounded),
            label: const Text('Show QR'),
            style: FilledButton.styleFrom(
              backgroundColor: udPurple,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: udText(17, weight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  Widget _qrStep({required bool automatic}) {
    final settings = _settings!;
    final payment = _payment;
    final Widget qr;
    if (automatic && payment?.qrImageUrl != null) {
      qr = Image.network(payment!.qrImageUrl!, width: 260, height: 260, fit: BoxFit.contain);
    } else {
      final data = automatic
          ? (payment?.payUrl ?? '')
          : upiLink(
              upiId: settings.upiId!,
              name: settings.upiName,
              amountPaise: _paise,
              note: _note.text.trim(),
            );
      qr = QrImageView(key: const Key('collect-qr'), data: data, size: 240, backgroundColor: Colors.white);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        UdCard(
          child: Column(
            children: [
              Text(rupees(_paise), key: const Key('collect-qr-amount'), style: udText(36, weight: FontWeight.w800)),
              if (_customer != null) Text('Udhaar of ${_customer!.name}', style: udText(13, color: udBody)),
              const SizedBox(height: 12),
              qr,
              const SizedBox(height: 12),
              Text(
                automatic
                    ? (payment?.qrImageUrl != null
                        ? 'Scan with any UPI app: PhonePe, GPay, Paytm'
                        : 'Scan with the phone camera or Google Lens, then pay with any UPI app')
                    : 'Scan with any UPI app. The money goes to ${settings.upiId}',
                textAlign: TextAlign.center,
                style: udText(13, color: udBody),
              ),
              const SizedBox(height: 12),
              if (automatic)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: udPurple),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text('Waiting for payment…',
                          key: const Key('collect-waiting'), style: udText(15, weight: FontWeight.w600)),
                    ),
                  ],
                ),
              if (automatic && payment?.testMode == true && payment?.payUrl != null)
                TextButton.icon(
                  key: const Key('collect-open-page'),
                  onPressed: () => _app.device.openLink(Uri.parse(payment!.payUrl!)),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Test: open the payment page on this phone'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 54,
                child: OutlinedButton(
                  key: const Key('collect-cancel'),
                  onPressed: _busy ? null : _cancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: udDue,
                    side: const BorderSide(color: udDue, width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text('Cancel', style: udText(16, weight: FontWeight.w700, color: udDue)),
                ),
              ),
            ),
            if (!automatic) ...[
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    key: const Key('collect-received'),
                    onPressed: _busy ? null : _manualReceived,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Money received'),
                    style: FilledButton.styleFrom(
                      backgroundColor: udPaid,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      textStyle: udText(16, weight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _paidStep() {
    final payment = _payment;
    final payer = payment?.payer;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
      children: [
        const Icon(Icons.check_circle_rounded, color: udPaid, size: 96),
        const SizedBox(height: 12),
        Text(
          '${rupees(payment?.amountPaise ?? _paise)} received',
          key: const Key('collect-paid'),
          textAlign: TextAlign.center,
          style: udText(30, weight: FontWeight.w800, color: udPaid),
        ),
        if (payer != null)
          Text('from $payer', textAlign: TextAlign.center, style: udText(15, color: udBody)),
        if (payment?.udhaarCustomerId != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Added to the udhaar book', textAlign: TextAlign.center, style: udText(13, color: udBody)),
          ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 54,
                child: OutlinedButton(
                  key: const Key('collect-done'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: udPurple,
                    side: const BorderSide(color: udPurple, width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text('Done', style: udText(16, weight: FontWeight.w700, color: udPurple)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 54,
                child: FilledButton(
                  key: const Key('collect-next'),
                  onPressed: _again,
                  style: FilledButton.styleFrom(
                    backgroundColor: udPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text('Next payment', style: udText(16, weight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.button,
    required this.buttonKey,
    required this.onPressed,
  });

  final IconData icon;
  final String text;
  final String button;
  final Key buttonKey;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: udPurple),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: udText(15, color: udBody)),
            const SizedBox(height: 16),
            FilledButton(
              key: buttonKey,
              onPressed: onPressed,
              style: FilledButton.styleFrom(backgroundColor: udPurple),
              child: Text(button),
            ),
          ],
        ),
      ),
    );
  }
}
