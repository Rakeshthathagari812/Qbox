import 'package:flutter/material.dart';

import '../onboarding_draft.dart';
import '../services/api_client.dart';
import '../services/app_services.dart';
import 'calendar_models.dart';
import 'calendar_style.dart';

/// Add a new event, or change / delete an existing one.
/// [existing] = editing; otherwise [draft] fills the form (e.g. from voice).
class EventFormScreen extends StatefulWidget {
  const EventFormScreen({
    required this.role,
    required this.draft,
    this.existing,
    this.fromVoice = false,
    super.key,
  });

  final QboxRole role;
  final EventDraft draft;
  final CalendarEvent? existing;

  /// Shows a note asking the user to check what was understood.
  final bool fromVoice;

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  late final TextEditingController _title = TextEditingController(
    text: widget.draft.title,
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.draft.note,
  );
  late DateTime _day = widget.draft.day;
  late int? _minute = widget.draft.minuteOfDay;
  late EventCategory _category = widget.draft.category;
  late Repeat _repeat = widget.draft.repeat;
  late int? _remind = widget.draft.remindMinutes;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _pickTime() async {
    final start = _minute ?? 10 * 60;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: start ~/ 60, minute: start % 60),
    );
    if (picked != null) {
      setState(() => _minute = picked.hour * 60 + picked.minute);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Enter a title');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final services = ServicesScope.of(context);
    final navigator = Navigator.of(context);
    final draft = EventDraft(
      title: title,
      day: _day,
      minuteOfDay: _minute,
      category: _category,
      repeat: _repeat,
      remindMinutes: _remind,
      note: _note.text,
    );
    try {
      if (_remind != null) await services.reminders.askPermission();
      if (_editing) {
        await services.calendar.update(widget.role, widget.existing!.id, draft);
      } else {
        await services.calendar.create(widget.role, draft);
      }
      if (mounted) navigator.pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.isNetwork
              ? 'Saving needs internet. Check your connection and try again.'
              : e.message,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this event?'),
        content: Text(
          widget.existing!.repeat == Repeat.none
              ? widget.existing!.title
              : '${widget.existing!.title}\nAll repeats will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('event-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: calRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final services = ServicesScope.of(context);
    final navigator = Navigator.of(context);
    try {
      await services.calendar.delete(widget.existing!.id);
      if (mounted) navigator.pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.isNetwork
              ? 'Deleting needs internet. Check your connection and try again.'
              : e.message,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: calBackground,
      appBar: AppBar(
        backgroundColor: calBackground,
        surfaceTintColor: Colors.transparent,
        foregroundColor: calInk,
        title: Text(
          _editing ? 'Edit event' : 'New event',
          style: calTitleStyle,
        ),
        actions: [
          if (_editing)
            IconButton(
              key: const Key('event-delete'),
              tooltip: 'Delete',
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded, color: calRed),
            ),
        ],
      ),
      body: SafeArea(
        // Short form: built all at once (not lazily), so Save always exists.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.fromVoice)
                Container(
                  key: const Key('event-voice-note'),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: calSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.mic_rounded, color: calPurple),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Here is what I understood. Check it, then tap Save.',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: calPurple,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              _Card(
                child: TextField(
                  key: const Key('event-title'),
                  controller: _title,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: calInk,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Title, e.g. Supplier payment',
                    border: InputBorder.none,
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _Card(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in EventCategory.values)
                      ChoiceChip(
                        key: Key('event-category-${c.code}'),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                        avatar: Icon(
                          categoryIcon(c),
                          size: 18,
                          color: _category == c
                              ? Colors.white
                              : categoryColor(c),
                        ),
                        label: Text(c.label),
                        showCheckmark: false,
                        selectedColor: categoryColor(c),
                        labelStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          color: _category == c ? Colors.white : calInk,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Card(
                child: Column(
                  children: [
                    _Row(
                      key: const Key('event-date'),
                      icon: Icons.calendar_today_rounded,
                      label: longDate(_day),
                      onTap: _pickDate,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      key: const Key('event-all-day'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      secondary: const Icon(
                        Icons.wb_sunny_outlined,
                        color: calPurple,
                      ),
                      title: const Text(
                        'All day',
                        style: TextStyle(fontFamily: 'Poppins'),
                      ),
                      value: _minute == null,
                      activeThumbColor: calPurple,
                      onChanged: (allDay) =>
                          setState(() => _minute = allDay ? null : 10 * 60),
                    ),
                    if (_minute != null) ...[
                      const Divider(height: 1),
                      _Row(
                        key: const Key('event-time'),
                        icon: Icons.access_time_rounded,
                        label: timeLabel(_minute!),
                        onTap: _pickTime,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Card(
                child: Column(
                  children: [
                    _Dropdown<Repeat>(
                      key: const Key('event-repeat'),
                      icon: Icons.repeat_rounded,
                      value: _repeat,
                      items: {for (final r in Repeat.values) r: r.label},
                      onChanged: (r) =>
                          setState(() => _repeat = r ?? Repeat.none),
                    ),
                    const Divider(height: 1),
                    _Dropdown<int?>(
                      key: const Key('event-reminder'),
                      icon: Icons.notifications_active_outlined,
                      value: reminderChoices.containsKey(_remind) ? _remind : 0,
                      items: reminderChoices,
                      onChanged: (m) => setState(() => _remind = m),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Card(
                child: TextField(
                  key: const Key('event-note'),
                  controller: _note,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 4,
                  style: const TextStyle(fontFamily: 'Poppins', color: calInk),
                  decoration: const InputDecoration(
                    hintText: 'Note (optional)',
                    border: InputBorder.none,
                    counterText: '',
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('event-error'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: calRed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  key: const Key('event-save'),
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: calPurple,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  icon: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_busy ? 'Saving…' : 'Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // A Material (not a coloured box), so tap ripples on rows inside show.
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: const Color(0x330E1B4D),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: child,
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: calPurple),
      title: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          color: calInk,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: calBody),
      onTap: onTap,
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 16, 0),
          child: Icon(icon, color: calPurple),
        ),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                color: calInk,
                fontSize: 15,
              ),
              items: [
                for (final entry in items.entries)
                  DropdownMenuItem<T>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
