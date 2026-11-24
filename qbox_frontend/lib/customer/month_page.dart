import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../udhaar/udhaar_models.dart' show rupees;
import '../udhaar/udhaar_widgets.dart';
import 'record_form_screen.dart';
import 'transaction_models.dart';

/// Loading one month of history, shared by Transaction History and Expenses:
/// the phone copy first, then the server's.
mixin MonthPage<T extends StatefulWidget> on State<T> {
  AppServices? _services;
  String? _month;
  MonthHistory? history;

  /// Every month with something, plus this month; newest first.
  List<String> _months = [];
  String? error;
  bool busy = false;

  AppServices get app => _services!;
  DateTime get now;
  String get month => _month ??= monthKey(now);

  /// Called when another month or a fresh copy is shown.
  void onMonthShown() {}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    load();
  }

  Future<void> load() async {
    final wanted = month;
    setState(() {
      busy = true;
      error = null;
    });
    final saved = await app.transactions.saved(wanted);
    if (!mounted || wanted != month) return;
    if (saved != null) setState(() => _show(saved));
    try {
      final fresh = await app.transactions.fresh(wanted);
      if (mounted && wanted == month) setState(() => _show(fresh));
    } on ApiException catch (e) {
      if (mounted && wanted == month) {
        setState(
          () => error = !e.isNetwork
              ? e.message
              : saved == null
              ? 'Offline: this month is not saved on this phone.'
              : 'Offline: showing the last saved copy.',
        );
      }
    } finally {
      if (mounted && wanted == month) setState(() => busy = false);
    }
  }

  void _show(MonthHistory value) {
    history = value;
    _months = ({monthKey(now), month, ...value.months}.toList()..sort()).reversed.toList();
    onMonthShown();
  }

  void go(String to) {
    setState(() {
      _month = to;
      history = null;
    });
    load();
  }

  /// Runs a change that needs internet, then loads again.
  Future<void> change(Future<void> Function() action, String done) async {
    setState(() => busy = true);
    try {
      await action();
      if (mounted) udNotify(context, done);
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.isNetwork ? 'This needs internet. Please try again.' : e.message);
    }
    if (mounted) await load();
  }

  Future<void> openForm() async {
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => RecordFormScreen(now: now)),
    );
    if (message == null || !mounted) return;
    udNotify(context, message);
    await load();
  }

  /// The same amount on the same day: maybe one payment recorded twice.
  Widget sameQuestion(Transaction mine, Transaction other) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 8),
      Text(
        'Is this the same payment as ${rupees(other.amountPaise)} to ${other.shopName}?',
        key: Key('same-${mine.id}'),
        style: udText(12, weight: FontWeight.w600, color: udWarn),
      ),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            key: Key('same-yes-${mine.id}'),
            onPressed: busy
                ? null
                : () => change(() => app.transactions.api.sameRecord(mine.recordId!), 'Counted once'),
            child: const Text('Yes, count once'),
          ),
          TextButton(
            key: Key('same-no-${mine.id}'),
            onPressed: busy
                ? null
                : () => change(() => app.transactions.api.differentRecord(mine.recordId!), 'Both counted'),
            child: const Text('No, count both'),
          ),
        ],
      ),
    ],
  );

  /// For one they said is the same as another, in case that was a mistake.
  Widget countAgain(Transaction mine) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      key: Key('count-${mine.id}'),
      onPressed: busy
          ? null
          : () => change(() => app.transactions.api.differentRecord(mine.recordId!), 'Counted'),
      child: const Text('Not the same? Count it'),
    ),
  );

  Widget monthBar() {
    final at = _months.indexOf(month);
    final older = at >= 0 && at + 1 < _months.length ? _months[at + 1] : null;
    final newer = at > 0 ? _months[at - 1] : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            key: const Key('transactions-older'),
            onPressed: older == null ? null : () => go(older),
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Earlier month',
          ),
          Expanded(
            child: Text(
              monthLabel(month),
              key: const Key('transactions-month'),
              textAlign: TextAlign.center,
              style: udText(16, weight: FontWeight.w700),
            ),
          ),
          IconButton(
            key: const Key('transactions-newer'),
            onPressed: newer == null ? null : () => go(newer),
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Later month',
          ),
        ],
      ),
    );
  }

  Widget errorBanner() => error == null
      ? const SizedBox.shrink()
      : UdBanner(
          key: const Key('transactions-error'),
          icon: Icons.wifi_off_rounded,
          text: error!,
          actionLabel: 'Retry',
          onAction: busy ? null : load,
        );

  Widget addButton() => FloatingActionButton.extended(
    key: const Key('record-add'),
    onPressed: openForm,
    backgroundColor: udPurple,
    foregroundColor: Colors.white,
    icon: const Icon(Icons.add_rounded),
    label: const Text('Add payment'),
  );
}
