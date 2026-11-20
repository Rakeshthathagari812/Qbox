import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calendar/calendar_models.dart' show isSameDay, longDate;
import '../services/api_client.dart';
import '../services/app_services.dart';
import 'udhaar_models.dart';
import 'udhaar_repository.dart';
import 'udhaar_widgets.dart';

/// Write one udhaar given or payment received for [customer].
/// Pops with the [SaveOutcome] when saved.
class UdhaarEntryForm extends StatefulWidget {
  const UdhaarEntryForm({
    required this.customer,
    required this.kind,
    this.amountPaise,
    this.fromVoice = false,
    this.heard = '',
    this.understood,
    this.now,
    super.key,
  });

  final UdhaarCustomer customer;
  final EntryKind kind;
  final int? amountPaise;
  final bool fromVoice;

  /// What the phone heard, and (for other languages) its English meaning.
  final String heard;
  final String? understood;

  /// For tests: pretend it is this moment.
  final DateTime? now;

  @override
  State<UdhaarEntryForm> createState() => _UdhaarEntryFormState();
}

class _UdhaarEntryFormState extends State<UdhaarEntryForm> {
  late final TextEditingController _amount;
  final _note = TextEditingController();
  late EntryKind _kind;
  late DateTime _day;
  String? _error;
  bool _saving = false;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _kind = widget.kind;
    _amount = TextEditingController(
      text: widget.amountPaise == null ? '' : paiseToText(widget.amountPaise!),
    );
    _day = DateTime(_now.year, _now.month, _now.day);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  int? get _paise => parsePaise(_amount.text);

  int get _newBalance {
    final p = _paise ?? 0;
    return widget.customer.balancePaise + (_kind == EntryKind.credit ? p : -p);
  }

  Future<void> _pickDay() async {
    final today = DateTime(_now.year, _now.month, _now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: 'Date of this entry',
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _save() async {
    final udhaar = ServicesScope.of(context).udhaar;
    final paise = _paise;
    if (paise == null) {
      setState(() => _error = 'Enter the amount');
      return;
    }
    if (paise > 100000000) {
      setState(() => _error = 'One entry can be at most ₹10,00,000');
      return;
    }
    final limit = widget.customer.creditLimitPaise;
    if (_kind == EntryKind.credit && limit != null && _newBalance > limit) {
      final go = await _confirmOverLimit(limit);
      if (go != true) return;
    }
    // Today = now; an earlier day (copying from the old notebook) = noon that day.
    final at = isSameDay(_day, _now)
        ? _now
        : DateTime(_day.year, _day.month, _day.day, 12);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final outcome = await udhaar.addEntry(
        widget.customer.id,
        EntryDraft(kind: _kind, amountPaise: paise, entryAt: at, note: _note.text),
      );
      if (mounted) Navigator.of(context).pop(outcome);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool?> _confirmOverLimit(int limit) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Credit limit crossed'),
        content: Text(
          '${widget.customer.name}\'s limit is ${rupees(limit)}. '
          'After this entry the total will be ${rupees(_newBalance)}.\n\nSave anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('limit-save-anyway'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: udDue),
            child: const Text('Save anyway'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final credit = _kind == EntryKind.credit;
    final color = credit ? udDue : udPaid;
    final today = isSameDay(_day, _now);
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(
              title: credit ? 'Udhaar given' : 'Payment received',
              subtitle: widget.customer.name,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.fromVoice)
                      Container(
                        key: const Key('entry-voice-note'),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: udSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.record_voice_over_rounded, color: udPurple),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Check what QBOX heard, then tap Save.',
                                    style: udText(13, weight: FontWeight.w600),
                                  ),
                                  if (widget.heard.isNotEmpty)
                                    Text(
                                      'Heard: "${widget.heard}"',
                                      key: const Key('entry-heard'),
                                      style: udText(12, color: udBody),
                                    ),
                                  if (widget.understood != null)
                                    Text(
                                      'Meaning: "${widget.understood}"',
                                      key: const Key('entry-understood'),
                                      style: udText(12, color: udBody),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    SegmentedButton<EntryKind>(
                      segments: const [
                        ButtonSegment(
                          value: EntryKind.credit,
                          label: Text('Udhaar given', key: Key('entry-kind-credit')),
                          icon: Icon(Icons.north_east_rounded),
                        ),
                        ButtonSegment(
                          value: EntryKind.payment,
                          label: Text('Payment', key: Key('entry-kind-payment')),
                          icon: Icon(Icons.south_west_rounded),
                        ),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (s) => setState(() => _kind = s.first),
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: color.withValues(alpha: 0.14),
                        selectedForegroundColor: color,
                        textStyle: udText(13, weight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 14),
                    UdCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Amount', style: udText(13, color: udBody)),
                          TextField(
                            key: const Key('entry-amount'),
                            controller: _amount,
                            autofocus: widget.amountPaise == null,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                              LengthLimitingTextInputFormatter(12),
                            ],
                            onChanged: (_) => setState(() => _error = null),
                            style: udText(34, weight: FontWeight.w800, color: color),
                            decoration: InputDecoration(
                              prefixText: '₹ ',
                              prefixStyle: udText(34, weight: FontWeight.w800, color: color),
                              hintText: '0',
                              border: InputBorder.none,
                            ),
                          ),
                          const Divider(),
                          Text(
                            'New balance: ${balanceLabel(_newBalance)}',
                            key: const Key('entry-new-balance'),
                            style: udText(13, weight: FontWeight.w600, color: balanceColor(_newBalance)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    UdCard(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: TextField(
                        key: const Key('entry-note'),
                        controller: _note,
                        maxLength: 200,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Note (optional)',
                          hintText: 'e.g. rice 5 kg, oil 1 litre',
                          border: InputBorder.none,
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      child: ListTile(
                        key: const Key('entry-date'),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        leading: const Icon(Icons.event_rounded, color: udPurple),
                        title: Text(today ? 'Today' : longDate(_day), style: udText(15, weight: FontWeight.w600)),
                        subtitle: Text(
                          today ? 'Tap to write an older entry' : 'Older entry (from the notebook)',
                          style: udText(12, color: udBody),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded, color: udPurple),
                        onTap: _pickDay,
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          key: const Key('entry-error'),
                          style: udText(13, weight: FontWeight.w600, color: udDue),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  key: const Key('entry-save'),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_rounded),
                  label: const Text('Save'),
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
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
