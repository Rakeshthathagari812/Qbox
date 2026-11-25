import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../services/device_actions.dart';
import '../udhaar/udhaar_models.dart' show rupees;
import '../udhaar/udhaar_widgets.dart';
import '../widgets/whatsapp_icon.dart';
import 'supply_models.dart';

/// Loading a supplier screen: the phone copy first, then the server's; and
/// answering, which needs internet.
mixin SupplyPage<T extends StatefulWidget, D extends Object> on State<T> {
  AppServices? _services;
  D? data;
  String? error;
  bool busy = false;

  AppServices get app => _services!;

  Future<D?> loadSaved();

  Future<D> loadFresh();

  /// Called when a copy is shown.
  void onShown() {}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    load();
  }

  void _show(D value) => setState(() {
    data = value;
    onShown();
  });

  Future<void> load() async {
    setState(() => busy = true);
    if (data == null) {
      final saved = await loadSaved();
      if (!mounted) return;
      if (saved != null && data == null) _show(saved);
    }
    try {
      final fresh = await loadFresh();
      if (mounted) {
        error = null;
        _show(fresh);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => error = !e.isNetwork
              ? e.message
              : data == null
              ? 'Offline: nothing is saved on this phone yet.'
              : 'Offline: showing the last saved copy.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Runs an answer, then loads again. True = it worked.
  Future<bool> act(Future<void> Function() action, String done) async {
    setState(() => busy = true);
    var ok = false;
    try {
      await action();
      ok = true;
      if (mounted) udNotify(context, done);
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.isNetwork ? 'This needs internet. Please try again.' : e.message);
    }
    if (mounted) await load();
    return ok;
  }

  /// "Yes, this came" (or "this is right").
  Future<void> confirmEntry(SupplyEntry e, String shop) async {
    final sure = await askSure(
      context,
      title: e.payment ? 'Did ${rupees(e.amountPaise)} come?' : 'Is ${rupees(e.amountPaise)} right?',
      text: e.payment
          ? 'Check your bank or cash first. It is taken off what $shop owes you. This cannot be undone.'
          : 'After this, neither of you can delete it. Goods you count leave your stock by themselves.',
      action: e.payment ? 'Yes, received' : 'Yes, right',
      color: udPaid,
    );
    if (!sure || !mounted) return;
    await act(() => app.supply.api.confirmEntry(e.id), e.payment ? 'Payment confirmed' : 'Confirmed');
  }

  Future<void> disputeEntry(SupplyEntry e, String shop) async {
    final reason = await askReason(
      context,
      title: e.payment ? 'Not received?' : 'Not right?',
      text: '$shop will see this and can correct it.',
      action: 'Send',
    );
    if (reason == null || !mounted) return;
    await act(() => app.supply.api.disputeEntry(e.id, reason), 'Sent to $shop');
  }

  Widget errorBanner() => error == null
      ? const SizedBox.shrink()
      : UdBanner(
          key: const Key('supply-error'),
          icon: Icons.wifi_off_rounded,
          text: error!,
          actionLabel: 'Retry',
          onAction: busy ? null : load,
        );

  /// Call and WhatsApp for a shop.
  List<Widget> contactButtons(String? phone, String key) => [
    if (phone != null && phone.isNotEmpty) ...[
      IconButton(
        key: Key('$key-call'),
        onPressed: () => app.device.openLink(callLink(phone)),
        icon: const Icon(Icons.call_rounded, color: udPurple),
        tooltip: 'Call',
      ),
      IconButton(
        key: Key('$key-whatsapp'),
        onPressed: () async {
          if (await app.device.openLink(whatsAppAppLink(phone, ''))) return;
          if (!await app.device.openLink(whatsAppLink(phone, '')) && mounted) {
            udNotify(context, 'WhatsApp is not installed on this phone.');
          }
        },
        icon: const WhatsAppIcon(),
        tooltip: 'WhatsApp',
      ),
    ],
  ];
}

/// Asks why. Null = cancelled.
Future<String?> askReason(
  BuildContext context, {
  required String title,
  required String text,
  required String action,
  bool needed = true,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ReasonDialog(title: title, text: text, action: action, needed: needed),
);

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.text, required this.action, required this.needed});

  final String title;
  final String text;
  final String action;
  final bool needed;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _done() {
    final reason = _reason.text.trim();
    if (reason.isEmpty && widget.needed) {
      setState(() => _error = 'Write why');
    } else {
      Navigator.of(context).pop(reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.text),
          TextField(
            key: const Key('reason'),
            controller: _reason,
            autofocus: true,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: widget.needed ? 'Why?' : 'Why? (optional)',
              errorText: _error,
              counterText: '',
            ),
            onSubmitted: (_) => _done(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('reason-done'),
          onPressed: _done,
          style: FilledButton.styleFrom(backgroundColor: udDue),
          child: Text(widget.action),
        ),
      ],
    );
  }
}

/// A yes/no question.
Future<bool> askSure(
  BuildContext context, {
  required String title,
  required String text,
  required String action,
  Color color = udPurple,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('sure'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: color),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// "₹5,000 to get", "₹200 advance", "All paid".
String toGetLabel(int paise) => paise > 0
    ? '${rupees(paise)} to get'
    : paise < 0
    ? '${rupees(paise)} advance'
    : 'All paid';
