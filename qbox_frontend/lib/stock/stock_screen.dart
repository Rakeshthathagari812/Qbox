import 'dart:async';

import 'package:flutter/material.dart';

import '../calculator/voice_services.dart';
import '../services/api_client.dart';
import '../services/app_services.dart';
import '../translator/languages.dart';
import '../translator/voice_language.dart';
import '../udhaar/udhaar_models.dart' show rupees, whenLabel;
import '../udhaar/udhaar_widgets.dart';
import 'item_form_screen.dart';
import 'item_screen.dart';
import 'quick_start_screen.dart';
import 'stock_catalog.dart';
import 'stock_models.dart';
import 'stock_repository.dart';
import 'stock_widgets.dart';
import 'voice_stock.dart';

/// Opens the shop's stock (the "Stock" home tile).
Widget openStock(BuildContext context) => const StockScreen();

/// Every item with how much is left, the stock's value, what is running low,
/// search, and stock in / sold by voice in 5 languages.
class StockScreen extends StatefulWidget {
  const StockScreen({this.now, super.key});

  /// For tests: pretend it is this moment.
  final DateTime? now;

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  AppServices? _services;
  StockBook? _book;
  bool _syncing = false;
  bool _offline = false;
  int _waiting = 0;
  bool _lowOnly = false;
  String _search = '';
  bool _listening = false;
  String _heard = '';
  AppLanguage _voiceLang = AppLanguage.english;

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
    if (_listening) unawaited(_app.voice.stop());
    super.dispose();
  }

  Future<void> _start() async {
    final saved = await _app.stock.savedBook();
    final waiting = await _app.stock.pendingCount();
    final lang = await readVoiceLanguage(_app.settings);
    if (!mounted) return;
    setState(() {
      _book = saved;
      _waiting = waiting;
      _voiceLang = lang;
    });
    await _sync();
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final report = await _app.stock.sendPending();
      final book = await _app.stock.freshBook();
      if (!mounted) return;
      setState(() {
        _book = book;
        _offline = false;
      });
      if (report.refused.isNotEmpty) {
        udNotify(context, 'An offline entry could not be saved: ${report.refused.first}');
      } else if (report.sent > 0) {
        udNotify(context, report.sent == 1 ? '1 offline entry is now saved' : '${report.sent} offline entries are now saved');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isNetwork) {
        final saved = await _app.stock.savedBook();
        if (!mounted) return;
        setState(() {
          _offline = true;
          _book = saved ?? _book;
        });
      } else {
        udNotify(context, e.isUnauthorized ? 'Your session has ended. Please log in again.' : e.message);
      }
    } finally {
      final waiting = await _app.stock.pendingCount();
      if (mounted) {
        setState(() {
          _syncing = false;
          _waiting = waiting;
        });
      }
    }
  }

  List<StockItem> get _shown {
    final q = _search.trim().toLowerCase();
    return [
      for (final i in _book?.items ?? const <StockItem>[])
        if ((!_lowOnly || i.isLow) &&
            (q.isEmpty ||
                i.name.toLowerCase().contains(q) ||
                (catalogItem(i.catalogCode)?.allNames.any((n) => n.toLowerCase().contains(q)) ?? false)))
          i,
    ];
  }

  Future<void> _pickVoiceLanguage() async {
    final picked = await pickVoiceLanguage(context, current: _voiceLang, settings: _app.settings, translator: _app.translator);
    if (picked != null && mounted) setState(() => _voiceLang = picked);
  }

  Future<void> _openItem(StockItem item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ItemScreen(item: item, language: _voiceLang, now: widget.now)),
    );
    if (mounted) await _sync();
  }

  Future<void> _addItem({CatalogItem? catalog, String name = '', int? opening}) async {
    final added = await Navigator.of(context).push<StockItem>(
      MaterialPageRoute(
        builder: (_) => ItemFormScreen(
          catalog: catalog,
          name: name,
          openingMilli: opening,
          pastItems: _book?.pastItems ?? const [],
        ),
      ),
    );
    if (added == null || !mounted) return;
    udNotify(context, '${added.name} added to your stock');
    await _sync();
  }

  /// Items the shop added itself (not plain ready-list ones): in stock now, or removed earlier.
  List<YourItem> get _yourItems => [
    for (final i in _book?.items ?? const <StockItem>[])
      if (catalogItem(i.catalogCode)?.en.toLowerCase() != i.name.toLowerCase())
        YourItem(name: i.name, unit: i.unit, catalogCode: i.catalogCode, inStock: true),
    for (final p in _book?.pastItems ?? const <PastItem>[])
      if (catalogItem(p.catalogCode)?.en.toLowerCase() != p.name.toLowerCase())
        YourItem(name: p.name, unit: p.unit, catalogCode: p.catalogCode),
  ];

  Future<void> _quickStart() async {
    final have = {
      for (final i in _book?.items ?? const <StockItem>[]) ...[?i.catalogCode, i.name.toLowerCase()],
    };
    final added = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => QuickStartScreen(inStock: have, yourItems: _yourItems, language: _voiceLang)),
    );
    if (added == null || !mounted) return;
    udNotify(context, added == 1 ? '1 item added' : '$added items added');
    await _sync();
  }

  Future<void> _move(StockItem item, {MoveKind kind = MoveKind.stockIn, int? qty, String heard = ''}) async {
    MoveSaved? outcome;
    final draft = await showMoveSheet(
      context,
      item: item,
      kind: kind,
      qtyMilli: qty,
      heard: heard,
      save: (d) async => outcome = await _app.stock.addMove(item.id, d),
    );
    if (draft == null || !mounted) return;
    await notifyIfNowLow(_app, item, draft);
    if (!mounted) return;
    udNotify(
      context,
      outcome == MoveSaved.savedOffline
          ? 'Saved on the phone: ${moveSummary(item, draft)}. It will sync when internet is back.'
          : 'Saved: ${moveSummary(item, draft)}',
    );
    await _sync();
  }

  Future<void> _voice() async {
    if (_listening) {
      await _app.voice.stop();
      return;
    }
    setState(() {
      _listening = true;
      _heard = '';
    });
    try {
      final words = await _app.voice.listen(
        localeId: _voiceLang.speechLocale,
        onWords: (w) {
          if (mounted) setState(() => _heard = w);
        },
      );
      if (!mounted) return;
      setState(() => _listening = false);
      if (words.trim().isEmpty) {
        udNotify(context, 'Did not hear anything. Tap Speak and say: rice 10 kg came');
        return;
      }
      final spoken = parseSpokenStock(words, _voiceLang, _book?.items ?? const []);
      if (spoken == null) {
        udNotify(context, 'Could not understand "$words". Try: rice 10 kg came, or sugar 2 kg sold');
        return;
      }
      StockItem? item;
      if (spoken.matches.length == 1) {
        item = spoken.matches.single;
      } else if (spoken.matches.length > 1) {
        item = await _whichItem(spoken.matches);
      } else if (spoken.newItem != null) {
        await _offerNew(spoken);
        return;
      } else {
        udNotify(context, 'Heard "$words". Say the item name too, like: rice 10 kg came');
        return;
      }
      if (item != null && mounted) {
        await _move(item, kind: spoken.kind ?? MoveKind.stockIn, qty: spoken.qtyFor(item), heard: words);
      }
    } on VoiceException catch (e) {
      if (mounted) udNotify(context, e.message);
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  Future<StockItem?> _whichItem(List<StockItem> matches) => showDialog<StockItem>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Which item?'),
      children: [
        for (final i in matches)
          SimpleDialogOption(
            key: Key('voice-item-${i.id}'),
            onPressed: () => Navigator.of(context).pop(i),
            child: Text('${i.name}  ·  ${formatQty(i.quantityMilli, i.unit)}', style: udText(15, weight: FontWeight.w600)),
          ),
      ],
    ),
  );

  Future<void> _offerNew(SpokenStock spoken) async {
    final c = spoken.newItem!;
    final add = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Not in your stock yet'),
        content: Text('Add ${c.en} (${c.nameIn(_voiceLang)}) to your stock?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('voice-add-item'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: udPurple),
            child: const Text('Add item'),
          ),
        ],
      ),
    );
    if (add != true || !mounted) return;
    final qty = spoken.qtyMilli;
    final unit = spoken.unit;
    final opening = spoken.kind == MoveKind.out || qty == null
        ? null
        : (unit == null ? qty : c.unit.convert(qty, unit) ?? qty);
    await _addItem(catalog: c, opening: opening);
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    final shown = _shown;
    final low = book?.lowCount ?? 0;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'Stock', subtitle: 'Inventory', busy: _syncing),
            if (_offline)
              const UdBanner(
                key: Key('stock-offline'),
                icon: Icons.wifi_off_rounded,
                text: 'Offline: showing your saved stock. New entries are kept on the phone.',
              ),
            if (_waiting > 0)
              UdBanner(
                key: const Key('stock-waiting'),
                icon: Icons.cloud_upload_outlined,
                color: udPurple,
                background: udSoft,
                text: _waiting == 1 ? '1 entry waiting to sync' : '$_waiting entries waiting to sync',
                actionLabel: 'Sync now',
                onAction: _syncing ? null : _sync,
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
                          Text('Stock value', style: udText(13, color: udBody)),
                          Text(
                            rupees(book?.totalValuePaise ?? 0),
                            key: const Key('stock-value'),
                            style: udText(30, weight: FontWeight.w800),
                          ),
                          Text(
                            (book?.items.length ?? 0) == 1 ? '1 item' : '${book?.items.length ?? 0} items',
                            style: udText(13, color: udBody),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              FilterChip(
                                key: const Key('stock-low-chip'),
                                selected: _lowOnly,
                                onSelected: (v) => setState(() => _lowOnly = v),
                                avatar: Icon(Icons.warning_amber_rounded, size: 18, color: low > 0 ? udDue : udBody),
                                label: Text(low == 1 ? '1 running low' : '$low running low'),
                              ),
                              ActionChip(
                                key: const Key('stock-quick-start'),
                                avatar: const Icon(Icons.playlist_add_check_rounded, size: 18, color: udPurple),
                                label: const Text('Add common items'),
                                onPressed: _quickStart,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('stock-search'),
                      onChanged: (v) => setState(() => _search = v),
                      decoration: InputDecoration(
                        hintText: 'Search items',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (book != null && book.items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            const Icon(Icons.inventory_2_outlined, size: 48, color: udPurple),
                            const SizedBox(height: 8),
                            Text(
                              'Your stock is empty.\nStart with common items, or add your own.',
                              key: const Key('stock-empty'),
                              textAlign: TextAlign.center,
                              style: udText(14, color: udBody),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              key: const Key('stock-quick-start-empty'),
                              onPressed: _quickStart,
                              icon: const Icon(Icons.playlist_add_check_rounded),
                              label: const Text('Add common items'),
                              style: FilledButton.styleFrom(backgroundColor: udPurple),
                            ),
                          ],
                        ),
                      )
                    else if (book != null && shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('No items match.', style: udText(14, color: udBody))),
                      ),
                    for (final i in shown) _ItemTile(item: i, local: localName(i, _voiceLang), now: _now, onTap: () => _openItem(i)),
                  ],
                ),
              ),
            ),
            if (_listening)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: udSoft, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  _heard.isEmpty ? 'Listening… say: rice 10 kg came' : _heard,
                  key: const Key('stock-heard'),
                  style: udText(14, weight: FontWeight.w600),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: VoiceLanguageChip(
                  key: const Key('stock-voice-lang'),
                  language: _voiceLang,
                  onPressed: _listening ? null : _pickVoiceLanguage,
                ),
              ),
            ),
            UdBottomButtons(
              leftKey: const Key('stock-speak'),
              leftIcon: _listening ? Icons.stop_rounded : Icons.mic_rounded,
              leftLabel: _listening ? 'Stop' : 'Speak',
              leftColor: _listening ? udDue : udPurple,
              onLeft: _voice,
              rightKey: const Key('stock-add'),
              rightIcon: Icons.add_box_outlined,
              rightLabel: 'Add item',
              onRight: _listening ? null : () => _addItem(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.local, required this.now, required this.onTap});

  final StockItem item;
  final String? local;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sub = [
      ?local,
      if (item.pricePaise != null) '${rupees(item.pricePaise!)}/${item.unit.short}',
      if (item.lastMoveAt != null) whenLabel(item.lastMoveAt!, now),
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: Key('stock-item-${item.id}'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: udText(15, weight: FontWeight.w700)),
                      if (sub.isNotEmpty)
                        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: udText(12, color: udBody)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatQty(item.quantityMilli, item.unit),
                      style: udText(16, weight: FontWeight.w700, color: qtyColor(item)),
                    ),
                    if (item.isLow) const UdBadge('Low'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
