import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calendar/calendar_models.dart' show isSameDay, longDate;
import '../services/api_client.dart';
import '../services/app_services.dart';
import '../udhaar/udhaar_models.dart';
import '../udhaar/udhaar_widgets.dart';
import 'transaction_models.dart';

/// Add a payment made outside QBOX (cash, another app). It cannot be changed or
/// deleted later, so it is checked once more. Closes with the message to show.
class RecordFormScreen extends StatefulWidget {
  const RecordFormScreen({this.now, super.key});

  final DateTime? now;

  @override
  State<RecordFormScreen> createState() => _RecordFormScreenState();
}

class _RecordFormScreenState extends State<RecordFormScreen> {
  final _amount = TextEditingController();
  final _title = TextEditingController();
  final _note = TextEditingController();
  ExpenseCategory _category = ExpenseCategory.groceries;
  late DateTime _at = _now;

  /// Kept for this form, so tapping Save again after a problem adds it once.
  final _clientRef = newClientRef();
  String? _amountError;
  String? _titleError;
  bool _busy = false;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _at.isAfter(_now) ? _now : _at,
      firstDate: DateTime(2000),
      lastDate: _now,
    );
    if (day == null || !mounted) return;
    // Today keeps the time now; another day keeps the time it had.
    final time = isSameDay(day, _now) ? _now : _at;
    setState(() => _at = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    final paise = parsePaise(_amount.text);
    final title = _title.text.trim();
    setState(() {
      _amountError = paise == null || paise < 100
          ? 'Enter at least ₹1'
          : paise > 100000000
          ? 'Enter up to ₹10,00,000'
          : null;
      _titleError = title.isEmpty ? 'Enter a name, like Tea stall' : null;
    });
    if (_amountError != null || _titleError != null) return;
    FocusScope.of(context).unfocus();
    final transactions = ServicesScope.of(context).transactions;
    if (!await _sure(paise!, title) || !mounted) return;
    final draft = RecordDraft(
      title: title,
      amountPaise: paise,
      category: _category,
      at: _at,
      note: _note.text,
      clientRef: _clientRef,
    );
    setState(() => _busy = true);
    try {
      final sent = await transactions.addRecord(draft);
      if (mounted) {
        Navigator.of(context).pop(sent ? 'Added' : 'Saved on this phone. It will be sent when there is internet.');
      }
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _sure(int paise, String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${rupees(paise)} to $title?'),
          content: Text(
            '${isSameDay(_at, _now) ? 'Today' : longDate(_at)}, ${_category.label}.\n\n'
            'Please check. It cannot be changed or deleted later.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Go back')),
            FilledButton(
              key: const Key('record-sure'),
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: udPurple),
              child: const Text('Save'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(
              title: 'Add payment',
              subtitle: 'Cash, or paid in another app',
              busy: _busy,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  UdCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Amount', style: udText(13, color: udBody)),
                        TextField(
                          key: const Key('record-amount'),
                          controller: _amount,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          style: udText(30, weight: FontWeight.w800),
                          decoration: InputDecoration(prefixText: '₹ ', errorText: _amountError),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('record-title'),
                          controller: _title,
                          maxLength: 80,
                          textCapitalization: TextCapitalization.sentences,
                          style: udText(15),
                          decoration: InputDecoration(
                            labelText: 'Paid to',
                            hintText: 'Tea stall, bus, Ravi',
                            counterText: '',
                            errorText: _titleError,
                          ),
                        ),
                        TextField(
                          key: const Key('record-note'),
                          controller: _note,
                          maxLength: 200,
                          style: udText(14),
                          decoration: const InputDecoration(labelText: 'Note (optional)', counterText: ''),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          key: const Key('record-day'),
                          onPressed: _pickDay,
                          icon: const Icon(Icons.calendar_today_rounded, size: 18),
                          label: Text(isSameDay(_at, _now) ? 'Today' : longDate(_at)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Category', style: udText(15, weight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  CategoryChips(selected: _category, onSelected: (c) => setState(() => _category = c)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  key: const Key('record-save'),
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: udPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: udText(17, weight: FontWeight.w700),
                  ),
                  child: const Text('Save'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CategoryChips extends StatelessWidget {
  const CategoryChips({required this.selected, required this.onSelected, super.key});

  final ExpenseCategory selected;
  final void Function(ExpenseCategory category) onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final c in ExpenseCategory.values)
          ChoiceChip(
            key: Key('category-${c.code}'),
            avatar: Icon(c.icon, size: 18, color: c.color),
            label: Text(c.label, style: udText(13, weight: FontWeight.w600)),
            selected: c == selected,
            showCheckmark: false,
            selectedColor: const Color(0xFFE6DCFF),
            backgroundColor: Colors.white,
            onSelected: (_) => onSelected(c),
          ),
      ],
    );
  }
}
