import 'package:flutter/material.dart';

import '../udhaar/udhaar_models.dart';
import '../udhaar/udhaar_widgets.dart';
import 'month_page.dart';
import 'transaction_models.dart';

/// Opens "Transaction History" (Customer home tile).
Widget openTransactions(BuildContext context) => const TransactionsScreen();

/// Everything the customer took on udhaar or paid, one month at a time: at
/// shops, and what they added themselves (in Expenses). Nothing here can be
/// added, changed or deleted. The last copy shows when offline.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({this.now, super.key});

  /// For tests: pretend it is this moment.
  final DateTime? now;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

/// The filter: everything, shops, or what they added.
const _all = 'all';
const _shops = 'shops';
const _others = 'others';

class _TransactionsScreenState extends State<TransactionsScreen> with MonthPage {
  String _filter = _all;

  @override
  DateTime get now => widget.now ?? DateTime.now();

  @override
  void onMonthShown() {
    if (_shown(history!.items).isEmpty) _filter = _all;
  }

  List<Transaction> _shown(List<Transaction> items) => switch (_filter) {
    _all => items,
    _shops => items.where((t) => !t.own).toList(),
    _ => items.where((t) => t.own).toList(),
  };

  @override
  Widget build(BuildContext context) {
    final all = history?.items ?? const <Transaction>[];
    final items = _shown(all);
    final same = possibleDuplicates(all);
    final own = totalOwn(items);
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'Transaction History', subtitle: 'Udhaar and payments', busy: busy),
            errorBanner(),
            monthBar(),
            if (all.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _chip('All', _all),
                    _chip('Shops', _shops),
                    _chip('Others', _others),
                  ],
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    UdCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: _total('Udhaar taken', totalTaken(items), udDue, 'transactions-taken')),
                              const SizedBox(width: 12),
                              Expanded(child: _total('Paid', totalPaid(items), udPaid, 'transactions-paid')),
                            ],
                          ),
                          if (own > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '${rupees(own)} of this was added by you.',
                                key: const Key('transactions-own'),
                                style: udText(12, color: udBody),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (history != null && items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          switch (_filter) {
                            _shops => 'Nothing from shops in ${monthLabel(month)}.',
                            _others => 'Nothing to others in ${monthLabel(month)}.',
                            _ => 'Nothing in ${monthLabel(month)}.',
                          },
                          key: const Key('transactions-empty'),
                          textAlign: TextAlign.center,
                          style: udText(14, color: udBody),
                        ),
                      ),
                    for (final t in items)
                      TransactionTile(
                        item: t,
                        now: now,
                        below: t.same
                            ? countAgain(t)
                            : same.containsKey(t.id)
                            ? sameQuestion(t, same[t.id]!)
                            : null,
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

  Widget _chip(String label, String key) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      key: Key('transactions-shop-$key'),
      label: Text(label, style: udText(12, weight: FontWeight.w600)),
      selected: _filter == key,
      selectedColor: const Color(0xFFE6DCFF),
      backgroundColor: Colors.white,
      onSelected: (_) => setState(() => _filter = key),
    ),
  );

  Widget _total(String label, int paise, Color color, String key) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: udText(13, color: udBody)),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(rupees(paise), key: Key(key), style: udText(24, weight: FontWeight.w800, color: color)),
      ),
    ],
  );
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({required this.item, required this.now, this.onTap, this.below, super.key});

  final Transaction item;
  final DateTime now;
  final VoidCallback? onTap;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final credit = item.kind == EntryKind.credit;
    final waiting = item.status == TransactionStatus.waiting;
    final color = waiting ? udWarn : !item.counts ? udBody : (credit ? udDue : udPaid);
    final strike = item.counts || waiting ? null : TextDecoration.lineThrough;
    return Container(
      key: Key('transaction-${item.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: item.counts || waiting ? Colors.white : const Color(0xFFF4F3F7),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Out when the customer paid, in when they took udhaar.
                    Icon(credit ? Icons.south_west_rounded : Icons.north_east_rounded, color: color, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.shopName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: udText(14, weight: FontWeight.w700, decoration: strike),
                          ),
                          Text(credit ? 'You took udhaar' : 'You paid', style: udText(12, color: udBody)),
                          if ((item.note ?? '').isNotEmpty)
                            Text(
                              item.note!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: udText(12, color: udBody),
                            ),
                          Text(whenLabel(item.at, now), style: udText(11, color: udBody)),
                          if (item.deleted)
                            Text(
                              'Deleted by the shop: ${item.deleteReason ?? ''}',
                              style: udText(11, weight: FontWeight.w600, color: udDue),
                            ),
                          Wrap(spacing: 6, runSpacing: 4, children: _badges()),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      rupees(item.amountPaise),
                      style: udText(16, weight: FontWeight.w700, color: color, decoration: strike),
                    ),
                  ],
                ),
                ?below,
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _badges() => [
    if (item.status == TransactionStatus.waiting) const UdBadge('Waiting for the shop to confirm', color: udWarn),
    if (item.status == TransactionStatus.notConfirmed) const UdBadge('Not confirmed by the shop'),
    if (item.online) UdBadge(item.testMode ? 'Online (test money)' : 'Online', color: udPurple),
    if (item.own) UdBadge(item.scanned ? 'Added by you · scanned QR' : 'Added by you', color: udBody),
    if (item.same) const UdBadge('Same as another payment: not counted', color: udWarn),
    if (item.pending) const UdBadge('Waiting for internet', color: udWarn),
  ];
}
