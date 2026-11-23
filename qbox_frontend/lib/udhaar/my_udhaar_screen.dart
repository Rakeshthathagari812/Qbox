import 'package:flutter/material.dart';

import '../calendar/calendar_models.dart' show longDate;
import '../payments/pay_udhaar.dart';
import '../services/api_client.dart';
import '../services/app_services.dart';
import '../services/device_actions.dart';
import 'udhaar_models.dart';
import 'udhaar_widgets.dart';

/// Opens "My Udhaar" (Customer home tile).
Widget openMyUdhaar(BuildContext context) => const MyUdhaarScreen();

/// The customer's own view: every shop that has written udhaar against their
/// mobile number, read-only.
class MyUdhaarScreen extends StatefulWidget {
  const MyUdhaarScreen({this.now, super.key});

  final DateTime? now;

  @override
  State<MyUdhaarScreen> createState() => _MyUdhaarScreenState();
}

class _MyUdhaarScreenState extends State<MyUdhaarScreen> {
  AppServices? _services;
  List<MyBook>? _books;
  bool _syncing = false;
  bool _offline = false;

  AppServices get _app => _services!;
  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    _start();
  }

  Future<void> _start() async {
    final saved = await _app.udhaar.savedMyBooks();
    if (!mounted) return;
    setState(() => _books = saved);
    await _sync();
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final books = await _app.udhaar.freshMyBooks();
      if (mounted) {
        setState(() {
          _books = books;
          _offline = false;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isNetwork) {
        setState(() => _offline = true);
      } else {
        udNotify(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _open(MyBook book) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => MyBookScreen(book: book, now: widget.now)),
    );
    if (mounted) await _sync();
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;
    final owed = books?.fold<int>(0, (s, b) => s + (b.balancePaise > 0 ? b.balancePaise : 0)) ?? 0;
    final shops = books?.where((b) => b.balancePaise > 0).length ?? 0;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'My Udhaar', subtitle: 'What I owe at shops', busy: _syncing),
            if (_offline)
              const UdBanner(
                key: Key('myudhaar-offline'),
                icon: Icons.wifi_off_rounded,
                text: 'Offline: showing the last saved copy.',
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _sync,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    UdCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('You owe in total', style: udText(13, color: udBody)),
                          Text(
                            rupees(owed),
                            key: const Key('myudhaar-total'),
                            style: udText(34, weight: FontWeight.w800, color: balanceColor(owed)),
                          ),
                          Text(
                            shops == 1 ? 'at 1 shop' : 'at $shops shops',
                            style: udText(13, color: udBody),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (books != null && books.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'No udhaar yet.\nWhen a shop adds you to its udhaar book, it shows here.',
                          key: const Key('myudhaar-empty'),
                          textAlign: TextAlign.center,
                          style: udText(14, color: udBody),
                        ),
                      ),
                    for (final b in books ?? const <MyBook>[])
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            key: Key('mybook-${b.bookId}'),
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => _open(b),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  const CircleAvatar(
                                    backgroundColor: udSoft,
                                    child: Icon(Icons.storefront_rounded, color: udPurple),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(b.shopName, style: udText(15, weight: FontWeight.w700)),
                                        if (b.lastEntryAt != null)
                                          Text(
                                            'Last: ${whenLabel(b.lastEntryAt!, _now)}',
                                            style: udText(12, color: udBody),
                                          ),
                                        if (b.dispute == Dispute.reported)
                                          const Padding(
                                            padding: EdgeInsets.only(top: 4),
                                            child: UdBadge('Reported: waiting for shop', color: udWarn),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    balanceLabel(b.balancePaise),
                                    style: udText(14, weight: FontWeight.w700, color: balanceColor(b.balancePaise)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One shop's entries for this customer (read-only), with "This is not me"
/// (a report the shop decides on; nothing is hidden by the customer alone).
class MyBookScreen extends StatefulWidget {
  const MyBookScreen({required this.book, this.now, super.key});

  final MyBook book;
  final DateTime? now;

  @override
  State<MyBookScreen> createState() => _MyBookScreenState();
}

class _MyBookScreenState extends State<MyBookScreen> {
  AppServices? _services;
  late MyBook _book;
  List<UdhaarEntry>? _entries;
  String? _error;
  bool _busy = false;

  AppServices get _app => _services!;
  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _book = widget.book;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final detail = await _app.udhaar.myBook(_book.bookId);
      if (mounted) {
        setState(() {
          _book = detail.book;
          _entries = detail.entries;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _notMe() async {
    final verified = _book.verifiedAt;
    final shop = _book.shopName;
    final checked = verified == null
        ? ''
        : 'Your number was checked with a code at $shop on ${longDate(verified)}.\n\n';
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report: this is not me?'),
        content: Text(
          '${checked}Your report goes to $shop to check. '
          'Nothing is hidden until the shop agrees it is the wrong number.',
          key: const Key('not-me-text'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('not-me-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: udDue),
            child: const Text('Send report'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await _change(_app.udhaar.notMe, 'Report sent. ${_book.shopName} will check it.');
  }

  /// Pays this shop online (Razorpay's payment screen); the book updates
  /// once the backend has checked the payment.
  Future<void> _pay() async {
    final message = await payUdhaar(
      context,
      _app,
      _book,
      onWorking: (working) {
        if (mounted) setState(() => _busy = working);
      },
    );
    if (!mounted || message == null) return;
    udNotify(context, message);
    await _load();
  }

  Future<void> _cancelReport() =>
      _change(_app.udhaar.cancelNotMe, 'Report taken back.');

  Future<void> _change(Future<MyBook> Function(int) action, String done) async {
    setState(() => _busy = true);
    try {
      final book = await action(_book.bookId);
      if (!mounted) return;
      setState(() => _book = book);
      udNotify(context, done);
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.isNetwork ? 'This needs internet. Please try again.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final balances = entries == null ? const <UdhaarEntry, int>{} : runningBalances(entries);
    final phone = _book.shopPhone;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: _book.shopName, subtitle: 'Udhaar at this shop', busy: _busy),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    UdCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _book.balancePaise > 0
                                      ? 'You owe'
                                      : (_book.balancePaise < 0 ? 'Advance paid' : 'All settled'),
                                  style: udText(13, color: udBody),
                                ),
                                Text(
                                  rupees(_book.balancePaise),
                                  key: const Key('mybook-balance'),
                                  style: udText(32, weight: FontWeight.w800, color: balanceColor(_book.balancePaise)),
                                ),
                              ],
                            ),
                          ),
                          if (phone != null && phone.isNotEmpty)
                            IconButton.filledTonal(
                              key: const Key('mybook-call'),
                              onPressed: () => _app.device.openLink(callLink(phone)),
                              icon: const Icon(Icons.call_rounded),
                              tooltip: 'Call the shop',
                            ),
                        ],
                      ),
                    ),
                    if (_book.balancePaise > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SizedBox(
                          height: 54,
                          child: FilledButton.icon(
                            key: const Key('mybook-pay'),
                            onPressed: _busy ? null : _pay,
                            icon: const Icon(Icons.payments_rounded),
                            label: Text('Pay ${rupees(_book.balancePaise)}'),
                            style: FilledButton.styleFrom(
                              backgroundColor: udPaid,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              textStyle: udText(16, weight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                    if (_book.dispute == Dispute.reported)
                      UdBanner(
                        key: const Key('mybook-reported'),
                        icon: Icons.hourglass_top_rounded,
                        text: 'You reported "this is not me". Waiting for ${_book.shopName} to check.',
                        actionLabel: 'Take back',
                        onAction: _busy ? null : _cancelReport,
                      ),
                    if (_book.dispute == Dispute.confirmed)
                      UdBanner(
                        key: const Key('mybook-confirmed'),
                        icon: Icons.verified_rounded,
                        color: udPurple,
                        background: udSoft,
                        text: '${_book.shopName} confirmed this is your number. '
                            'Please talk to the shop if you disagree.',
                      ),
                    const SizedBox(height: 16),
                    if (_error != null)
                      UdBanner(
                        key: const Key('mybook-error'),
                        icon: Icons.wifi_off_rounded,
                        text: _error!,
                        actionLabel: 'Retry',
                        onAction: _load,
                      ),
                    if (entries != null) ...[
                      Text('History', style: udText(16, weight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      for (final e in entries)
                        EntryTile(
                          entry: e,
                          balanceAfter: balances[e] ?? 0,
                          now: _now,
                          forCustomer: true,
                        ),
                      const SizedBox(height: 16),
                      if (_book.dispute == Dispute.none)
                        Center(
                        child: TextButton.icon(
                          key: const Key('mybook-not-me'),
                          onPressed: _busy ? null : _notMe,
                          icon: const Icon(Icons.report_outlined, color: udDue),
                          label: Text('This is not me', style: udText(14, weight: FontWeight.w600, color: udDue)),
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
}
