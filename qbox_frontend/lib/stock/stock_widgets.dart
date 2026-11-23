import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../translator/languages.dart';
import '../udhaar/udhaar_widgets.dart';
import 'stock_catalog.dart';
import 'stock_models.dart';

/// The item's name in the shop's language as well, when it came from the
/// ready list ("Rice · బియ్యం").
String? localName(StockItem item, AppLanguage language) {
  if (language == AppLanguage.english) return null;
  final local = catalogItem(item.catalogCode)?.nameIn(language);
  return local == null || local == item.name ? null : local;
}

Color qtyColor(StockItem item) => item.quantityMilli < 0 || item.isLow ? udDue : udInk;

/// "Running low" phone notification when [move] takes [before] to or below its
/// alert level (only the first time it crosses, not every sale after).
Future<void> notifyIfNowLow(AppServices app, StockItem before, MoveDraft move) async {
  final alert = before.alertMilli;
  if (alert == null) return;
  final effect = StockMove.pending(move).effect;
  final after = before.quantityMilli + effect;
  if (before.quantityMilli <= alert || after > alert) return;
  await app.reminders.askPermission();
  await app.reminders.showNow(
    id: before.id,
    title: 'Running low: ${before.name}',
    body: after <= 0
        ? 'Out of stock. Order more soon.'
        : 'Only ${formatQty(after, before.unit)} left. Order more soon.',
  );
}

/// What a move did, for messages: "Rice +10 kg", "Sugar −2 kg".
String moveSummary(StockItem item, MoveDraft move) {
  final effect = StockMove.pending(move).effect;
  final sign = effect >= 0 ? '+' : '−';
  return '${item.name} $sign${formatQty(effect.abs(), item.unit)}';
}

/// Stock in / sold / corrected: the sheet where the shopkeeper checks and
/// saves a move. Returns the saved draft, or null if closed.
Future<MoveDraft?> showMoveSheet(
  BuildContext context, {
  required StockItem item,
  required Future<void> Function(MoveDraft draft) save,
  MoveKind kind = MoveKind.stockIn,
  int? qtyMilli,
  String heard = '',
}) {
  return showModalBottomSheet<MoveDraft>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MoveSheet(item: item, save: save, kind: kind, qtyMilli: qtyMilli, heard: heard),
  );
}

class _MoveSheet extends StatefulWidget {
  const _MoveSheet({required this.item, required this.save, required this.kind, this.qtyMilli, this.heard = ''});

  final StockItem item;
  final Future<void> Function(MoveDraft draft) save;
  final MoveKind kind;
  final int? qtyMilli;
  final String heard;

  @override
  State<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<_MoveSheet> {
  late MoveKind _kind = widget.kind;
  late final _qty = TextEditingController(text: widget.qtyMilli == null ? '' : qtyNumber(widget.qtyMilli!));
  final _note = TextEditingController();
  String? _error;
  bool _saving = false;

  StockItem get _item => widget.item;

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  /// The move as typed, or null (with [_error] set) if something is missing.
  MoveDraft? _draft() {
    final qty = parseQty(_qty.text);
    final note = _note.text.trim();
    if (_kind == MoveKind.adjust) {
      if (qty == null) return _fail('Enter the count you have now');
      final change = qty - _item.quantityMilli;
      if (change == 0) return _fail('The count is already ${formatQty(qty, _item.unit)}');
      if (note.isEmpty) return _fail('Write why: damaged, expired, counted wrong…');
      return MoveDraft(kind: _kind, qtyMilli: change, moveAt: DateTime.now(), note: note);
    }
    if (qty == null || qty <= 0) return _fail('Enter how much');
    return MoveDraft(kind: _kind, qtyMilli: qty, moveAt: DateTime.now(), note: note);
  }

  MoveDraft? _fail(String message) {
    setState(() => _error = message);
    return null;
  }

  Future<void> _save() async {
    final draft = _draft();
    if (draft == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(draft);
      if (mounted) Navigator.of(context).pop(draft);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final qty = parseQty(_qty.text);
    final adjust = _kind == MoveKind.adjust;
    String? hint;
    if (_kind == MoveKind.out && qty != null && qty > _item.quantityMilli) {
      hint = 'Only ${formatQty(_item.quantityMilli, _item.unit)} in stock. Saving still works.';
    } else if (adjust && qty != null && qty != _item.quantityMilli) {
      final change = qty - _item.quantityMilli;
      hint = 'Change: ${change > 0 ? '+' : '−'}${formatQty(change.abs(), _item.unit)}';
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_item.name, style: udText(20, weight: FontWeight.w700)),
            Text('In stock: ${formatQty(_item.quantityMilli, _item.unit)}', style: udText(13, color: udBody)),
            if (widget.heard.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Heard: "${widget.heard}"', style: udText(12, color: udBody)),
              ),
            const SizedBox(height: 12),
            SegmentedButton<MoveKind>(
              key: const Key('move-kind'),
              segments: const [
                ButtonSegment(value: MoveKind.stockIn, label: Text('Stock in'), icon: Icon(Icons.add_rounded)),
                ButtonSegment(value: MoveKind.out, label: Text('Sold'), icon: Icon(Icons.remove_rounded)),
                ButtonSegment(value: MoveKind.adjust, label: Text('Correct'), icon: Icon(Icons.edit_outlined)),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() {
                _kind = s.first;
                _error = null;
                if (_kind == MoveKind.adjust && _qty.text.isEmpty) _qty.text = qtyNumber(_item.quantityMilli);
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('move-qty'),
              controller: _qty,
              autofocus: widget.qtyMilli == null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: udText(26, weight: FontWeight.w800),
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: adjust ? 'Count you have now' : (_kind == MoveKind.out ? 'How much sold' : 'How much came in'),
                suffixText: _item.unit.short,
              ),
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(hint, key: const Key('move-hint'), style: udText(12, weight: FontWeight.w600, color: udWarn)),
              ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('move-note'),
              controller: _note,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: adjust ? 'Reason (damaged, expired, counted wrong)' : 'Note (optional), e.g. supplier name',
                counterText: '',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, key: const Key('move-error'), style: udText(13, weight: FontWeight.w600, color: udDue)),
              ),
            const SizedBox(height: 16),
            SizedBox(
              height: 54,
              child: FilledButton(
                key: const Key('move-save'),
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: _kind == MoveKind.out ? udDue : (adjust ? udWarn : udPaid),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  textStyle: udText(16, weight: FontWeight.w700),
                ),
                child: Text(_saving ? 'Saving…' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
