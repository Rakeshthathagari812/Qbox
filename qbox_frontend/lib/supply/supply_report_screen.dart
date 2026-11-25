import 'package:flutter/material.dart';

import '../stock/stock_models.dart' show formatQty;
import '../suppliers/supplier_models.dart' show OrderStatus, shortDay;
import '../udhaar/udhaar_models.dart' show rupees;
import '../udhaar/udhaar_widgets.dart';
import 'supply_models.dart';
import 'supply_page.dart';

/// Opens "Reports" (Supplier home tile).
Widget openSupplyReport(BuildContext context) => const SupplyReportScreen();

/// Ready periods. Both days are included.
enum ReportPeriod {
  thisMonth('This month'),
  lastMonth('Last month'),
  threeMonths('3 months'),
  thisYear('This year'),
  custom('Choose dates');

  const ReportPeriod(this.label);

  final String label;

  (DateTime, DateTime) days(DateTime now) => switch (this) {
    lastMonth => (DateTime(now.year, now.month - 1), DateTime(now.year, now.month, 0)),
    threeMonths => (DateTime(now.year, now.month - 2), DateTime(now.year, now.month, now.day)),
    thisYear => (DateTime(now.year), DateTime(now.year, now.month, now.day)),
    _ => (DateTime(now.year, now.month), DateTime(now.year, now.month, now.day)),
  };
}

/// What was given and got, by shop and by product.
class SupplyReportScreen extends StatefulWidget {
  const SupplyReportScreen({this.now, super.key});

  final DateTime? now;

  @override
  State<SupplyReportScreen> createState() => _SupplyReportScreenState();
}

class _SupplyReportScreenState extends State<SupplyReportScreen> with SupplyPage<SupplyReportScreen, SupplyReport> {
  ReportPeriod _period = ReportPeriod.thisMonth;
  late DateTime _start = _period.days(_now).$1;
  late DateTime _end = _period.days(_now).$2;

  DateTime get _now => widget.now ?? DateTime.now();

  String get _dates => '${shortDay(_start, _now)} to ${shortDay(_end, _now)}';

  @override
  Future<SupplyReport?> loadSaved() async => null;

  @override
  Future<SupplyReport> loadFresh() => app.supply.api.report(_start, _end);

  Future<void> _choose(ReportPeriod period) async {
    var (start, end) = period.days(_now);
    if (period == ReportPeriod.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(_now.year - 1),
        lastDate: DateTime(_now.year, _now.month, _now.day),
        initialDateRange: DateTimeRange(start: _start, end: _end),
        currentDate: _now,
      );
      if (picked == null || !mounted) return;
      (start, end) = (picked.start, picked.end);
    }
    setState(() {
      _period = period;
      _start = start;
      _end = end;
      data = null; // another period's numbers must never stay on the screen
    });
    await load();
  }

  Future<void> _share() async {
    final r = data!;
    final text = [
      'QBOX report, $_dates',
      'Goods given: ${rupees(r.givenPaise)}',
      'Payments received: ${rupees(r.receivedPaise)}',
      'Still to get now: ${rupees(r.toGetPaise)}',
      if (r.shops.isNotEmpty) '',
      for (final s in r.shops.take(30))
        '${s.name}: given ${rupees(s.givenPaise)}, received ${rupees(s.receivedPaise)}, to get ${rupees(s.toGetPaise)}',
    ].join('\n');
    final opened = await app.device.openLink(Uri(scheme: 'whatsapp', host: 'send', queryParameters: {'text': text}));
    if (!opened && mounted) udNotify(context, 'WhatsApp is not installed on this phone.');
  }

  @override
  Widget build(BuildContext context) {
    final r = data;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(
              title: 'Reports',
              subtitle: _dates,
              busy: busy,
              actions: [
                IconButton(
                  key: const Key('report-share'),
                  onPressed: r == null || busy ? null : _share,
                  icon: const Icon(Icons.share_rounded),
                  color: udPurple,
                  tooltip: 'Share on WhatsApp',
                ),
              ],
            ),
            errorBanner(),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  for (final p in ReportPeriod.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: Key('report-${p.name}'),
                        label: Text(p.label),
                        labelStyle: udText(13, weight: FontWeight.w600, color: _period == p ? Colors.white : udInk),
                        selected: _period == p,
                        selectedColor: udPurple,
                        showCheckmark: false,
                        backgroundColor: Colors.white,
                        onSelected: busy ? null : (_) => _choose(p),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: r == null ? const [] : _body(r),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(SupplyReport r) => [
    UdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _figure('report-given', 'Goods given', r.givenPaise, udInk),
              const SizedBox(width: 12),
              _figure('report-received', 'Received', r.receivedPaise, udPaid),
            ],
          ),
          const Divider(height: 22),
          Row(
            children: [
              _figure('report-to-get', 'Still to get, today', r.toGetPaise, udDue),
              const SizedBox(width: 12),
              _figure('report-waiting', 'Paid, not confirmed', r.waitingPaise, udWarn),
            ],
          ),
        ],
      ),
    ),
    const SizedBox(height: 12),
    UdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            r.orderCount == 1 ? '1 order' : '${r.orderCount} orders',
            key: const Key('report-orders'),
            style: udText(16, weight: FontWeight.w700),
          ),
          if (r.orderCount > 0)
            Text(
              [
                for (final s in OrderStatus.values)
                  if ((r.orders[s] ?? 0) > 0) '${supplyStatus(s)}: ${r.orders[s]}',
              ].join(', '),
              style: udText(13, color: udBody),
            ),
        ],
      ),
    ),
    _heading('By shop'),
    if (r.shops.isEmpty) _none('report-no-shops', 'Nothing with any shop in these days.'),
    for (final s in r.shops)
      _row(
        s.connected ? s.name : '${s.name} (disconnected)',
        'Received ${rupees(s.receivedPaise)}, ${toGetLabel(s.toGetPaise)}',
        rupees(s.givenPaise),
        s.givenPaise,
        r.shops.first.givenPaise,
      ),
    _heading('By product'),
    if (r.products.isEmpty) _none('report-no-products', 'No items are written on the bills of these days.'),
    for (final p in r.products)
      _row(
        p.name,
        formatQty(p.qtyMilli, p.unit),
        p.amountPaise == null ? '' : rupees(p.amountPaise!),
        p.amountPaise ?? 0,
        r.products.first.amountPaise ?? 0,
      ),
  ];

  Widget _figure(String key, String label, int paise, Color color) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: udText(12, color: udBody)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(rupees(paise), key: Key(key), style: udText(22, weight: FontWeight.w800, color: color)),
        ),
      ],
    ),
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
    child: Text(text, style: udText(16, weight: FontWeight.w700)),
  );

  Widget _none(String key, String text) => Text(text, key: Key(key), style: udText(13, color: udBody));

  /// With a bar, longest for the biggest.
  Widget _row(String title, String detail, String amount, int value, int most) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: udText(14, weight: FontWeight.w700))),
            const SizedBox(width: 8),
            Text(amount, style: udText(15, weight: FontWeight.w700)),
          ],
        ),
        Text(detail, style: udText(12, color: udBody)),
        if (value > 0 && most > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (value / most).clamp(0.02, 1.0),
                minHeight: 6,
                color: udPurple,
                backgroundColor: udSoft,
              ),
            ),
          ),
      ],
    ),
  );
}
