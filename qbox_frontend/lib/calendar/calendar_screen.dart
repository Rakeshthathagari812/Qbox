import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calculator/voice_services.dart';
import '../onboarding_draft.dart';
import '../services/api_client.dart';
import '../services/app_services.dart';
import '../translator/languages.dart';
import '../translator/voice_language.dart';
import 'calendar_models.dart';
import 'calendar_style.dart';
import 'event_form_screen.dart';
import 'reminders.dart';
import 'spoken_time.dart';
import 'voice_event.dart';

/// Opens the Shop calendar (Business home tile).
Widget openShopCalendar(BuildContext context) =>
    const CalendarScreen(role: QboxRole.business);

/// Opens the personal calendar (Customer home tile).
Widget openCustomerCalendar(BuildContext context) =>
    const CalendarScreen(role: QboxRole.customer);

/// Opens the Supplier calendar (the "Calendar" home tile).
Widget openSupplierCalendar(BuildContext context) =>
    const CalendarScreen(role: QboxRole.supplier);

/// Month view, the chosen day's events and festivals, and adding events by
/// typing or by voice. Events are saved on the server; a copy is kept on the
/// phone so the calendar still opens offline.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({required this.role, this.today, super.key});

  final QboxRole role;

  /// For tests: pretend today is this date.
  final DateTime? today;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> with WidgetsBindingObserver {
  AppServices? _services;
  late final DateTime _today;
  late DateTime _month;
  late DateTime _selected;
  List<CalendarEvent> _events = const [];
  List<Festival> _festivals = const [];
  bool _syncing = false;
  bool _offline = false;
  bool _listening = false;

  /// The microphone is really open (else it is still getting ready).
  bool _micOpen = false;
  ReminderProblem _problem = ReminderProblem.none;
  int _unsent = 0;
  String _heard = '';
  AppLanguage _voiceLang = AppLanguage.english;

  AppServices get _app => _services!;

  EventCategory get _defaultCategory => widget.role != QboxRole.customer
      ? EventCategory.shop
      : EventCategory.personal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = widget.today ?? DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _month = DateTime(_today.year, _today.month);
    _selected = _today;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the phone's settings: set the reminders at the exact time.
    if (state == AppLifecycleState.resumed && _services != null) unawaited(_checkReminders());
  }

  Future<void> _checkReminders() async {
    final before = _problem;
    final now = await _app.reminders.problem();
    if (now == ReminderProblem.none && before != now) await _app.reminders.sync(widget.role, _events);
    if (mounted && now != before) setState(() => _problem = now);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_listening) unawaited(_app.voice.stop());
    super.dispose();
  }

  Future<void> _start() async {
    // 1. Show the saved copy straight away (works offline).
    final events = await _app.calendarStore.loadEvents(widget.role);
    final festivals = await _app.calendarStore.loadFestivals();
    final lang = await readVoiceLanguage(_app.settings);
    if (!mounted) return;
    setState(() {
      _events = events ?? const [];
      _festivals = festivals ?? const [];
      _voiceLang = lang;
    });
    unawaited(_checkReminders());
    final voice = _app.voice;
    if (voice is VoiceWarmUp) unawaited((voice as VoiceWarmUp).warmUp(localeId: lang.speechLocale));
    // 2. Then fetch the latest from the server.
    await _sync();
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final events = await _app.calendar.events(widget.role);
      final festivals = await _app.calendar.festivals();
      await _app.calendarStore.saveFestivals(festivals);
      unawaited(_app.reminders.sync(widget.role, events));
      if (!mounted) return;
      setState(() {
        _events = events;
        _festivals = festivals;
        _offline = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isNetwork) {
        // The copy on the phone, with what was added here since.
        final here = await _app.calendarStore.loadEvents(widget.role);
        if (!mounted) return;
        setState(() {
          _offline = true;
          _events = here ?? _events;
        });
      } else {
        _notify(
          e.isUnauthorized
              ? 'Your session has ended. Please log in again.'
              : e.message,
        );
      }
    } finally {
      final unsent = await _app.calendar.pendingCount();
      if (mounted) {
        setState(() {
          _syncing = false;
          _unsent = unsent;
        });
      }
    }
  }

  /// Short messages float just above the Speak / Add buttons, never over them.
  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        ),
      );
  }

  List<CalendarEvent> _eventsOn(DateTime day) {
    final list = _events.where((e) => e.occursOn(day)).toList();
    list.sort((a, b) => (a.minuteOfDay ?? -1).compareTo(b.minuteOfDay ?? -1));
    return list;
  }

  List<Festival> _festivalsOn(DateTime day) =>
      _festivals.where((f) => isSameDay(f.day, day)).toList();

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  void _goToday() {
    setState(() {
      _month = DateTime(_today.year, _today.month);
      _selected = _today;
    });
  }

  Future<void> _pickVoiceLanguage() async {
    final picked = await pickVoiceLanguage(
      context,
      current: _voiceLang,
      settings: _app.settings,
      translator: _app.translator,
    );
    if (picked != null && mounted) setState(() => _voiceLang = picked);
  }

  Future<void> _openForm({
    required EventDraft draft,
    CalendarEvent? existing,
    bool fromVoice = false,
    String heard = '',
    String? understood,
  }) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EventFormScreen(
          role: widget.role,
          draft: draft,
          existing: existing,
          fromVoice: fromVoice,
          heard: heard,
          understood: understood,
        ),
      ),
    );
    if (changed == true && mounted) {
      // Jump to the saved event's month so the user sees it.
      setState(() {
        _selected = DateTime(draft.day.year, draft.day.month, draft.day.day);
        _month = DateTime(draft.day.year, draft.day.month);
      });
      await _sync();
      await _checkReminders();
      if (mounted) {
        _notify(
          _offline
              ? 'Saved on this phone. It will be sent when there is internet.'
              : existing == null
              ? 'Event saved'
              : 'Event updated',
        );
      }
    }
  }

  void _addEvent() {
    _openForm(
      draft: EventDraft(
        title: '',
        day: _selected,
        minuteOfDay: 10 * 60,
        category: _defaultCategory,
        remindMinutes: 0,
      ),
    );
  }

  Future<void> _fixReminders() async {
    final go = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _OnTimeSheet(problem: _problem),
    );
    if (go == null || !mounted) return;
    if (go && _problem == ReminderProblem.notExact) {
      await _app.reminders.askExactTime();
      await _checkReminders();
    } else if (!await _app.device.openAppSettings() && mounted) {
      _notify('Open phone Settings > Apps > QBOX');
    }
  }

  Future<void> _voiceAdd() async {
    if (_listening) {
      await _app.voice.stop();
      return;
    }
    setState(() {
      _listening = true;
      _micOpen = false;
      _heard = '';
    });
    try {
      final words = await _app.voice.listen(
        localeId: _voiceLang.speechLocale,
        pace: const VoicePace(pause: Duration(milliseconds: 1400), serverPause: Duration(milliseconds: 1100)),
        onReady: () {
          if (!mounted || !_listening) return;
          HapticFeedback.mediumImpact();
          setState(() => _micOpen = true);
        },
        onWords: (w) {
          if (mounted) setState(() => _heard = w);
        },
      );
      if (!mounted) return;
      if (words.trim().isEmpty) {
        _notify('Did not hear anything. Tap Speak and say your reminder.');
        return;
      }
      setState(() => _listening = false);
      // Other languages: translated to English on the phone, then the date,
      // time and title are read from that. The title is saved in English.
      final english = await voiceToEnglish(
        context,
        words: words,
        language: _voiceLang,
        translator: _app.translator,
        onError: _notify,
      );
      if (english == null || !mounted) return;
      final draft = parseSpokenEvent(
        english,
        widget.today ?? DateTime.now(),
        defaultCategory: _defaultCategory,
        spokenTime: nativeTime(words, _voiceLang),
      );
      if (draft == null) {
        _notify(
          'Could not understand "$words". Try: remind me tomorrow 10 am supplier payment',
        );
        return;
      }
      await _openForm(
        draft: draft,
        fromVoice: true,
        heard: words,
        understood: _voiceLang == AppLanguage.english ? null : english,
      );
    } on VoiceException catch (e) {
      if (mounted) _notify(e.message);
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayEvents = _eventsOn(_selected);
    final dayFestivals = _festivalsOn(_selected);
    return Scaffold(
      backgroundColor: calBackground,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _Header(
                title: switch (widget.role) {
                  QboxRole.business => 'Shop Calendar',
                  QboxRole.customer => 'My Calendar',
                  QboxRole.supplier => 'Supply Calendar',
                },
                syncing: _syncing,
                onBack: () => Navigator.of(context).pop(),
                onToday: _goToday,
              ),
            ),
            if (_offline)
              Container(
                key: const Key('calendar-offline'),
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      size: 18,
                      color: festivalColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _unsent > 0
                            ? 'Offline: saved on this phone. $_unsent to send when there is internet.'
                            : 'Offline: showing your saved calendar. You can still add; reminders still ring.',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: calInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_problem != ReminderProblem.none) _OnTimeCard(problem: _problem, onFix: _fixReminders),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _sync,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    _MonthCard(
                      month: _month,
                      today: _today,
                      selected: _selected,
                      onPrev: () => _changeMonth(-1),
                      onNext: () => _changeMonth(1),
                      onPick: (day) => setState(() {
                        _selected = day;
                        if (day.month != _month.month) {
                          _month = DateTime(day.year, day.month);
                        }
                      }),
                      dotsFor: (day) => [
                        if (_festivalsOn(day).isNotEmpty) festivalColor,
                        for (final e in _eventsOn(day).take(3))
                          categoryColor(e.category),
                      ],
                      isFestival: (day) => _festivalsOn(day).isNotEmpty,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isSameDay(_selected, _today)
                          ? 'Today · ${longDate(_selected)}'
                          : longDate(_selected),
                      key: const Key('calendar-day-title'),
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: calInk,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final f in dayFestivals) _FestivalCard(festival: f),
                    for (final e in dayEvents)
                      _EventCard(
                        event: e,
                        onTap: () => _openForm(draft: e, existing: e),
                      ),
                    if (dayFestivals.isEmpty && dayEvents.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'Nothing planned. Tap Add or Speak.',
                            key: Key('calendar-empty'),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: calBody,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_listening) _ListeningBar(heard: _heard, open: _micOpen),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: VoiceLanguageChip(
                  key: const Key('calendar-voice-lang'),
                  language: _voiceLang,
                  onPressed: _listening ? null : _pickVoiceLanguage,
                ),
              ),
            ),
            _BottomBar(
              listening: _listening,
              micOpen: _micOpen,
              onSpeak: _voiceAdd,
              onAdd: _listening ? null : _addEvent,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.syncing,
    required this.onBack,
    required this.onToday,
  });

  final String title;
  final bool syncing;
  final VoidCallback onBack;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            key: const Key('calendar-back'),
            customBorder: const CircleBorder(),
            onTap: onBack,
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.arrow_back, color: calPurple),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: calTitleStyle)),
        if (syncing)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: calPurple,
              ),
            ),
          ),
        TextButton.icon(
          key: const Key('calendar-today'),
          onPressed: onToday,
          icon: const Icon(Icons.today_rounded, size: 18),
          label: const Text('Today'),
          style: TextButton.styleFrom(
            foregroundColor: calPurple,
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({
    required this.month,
    required this.today,
    required this.selected,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
    required this.dotsFor,
    required this.isFestival,
  });

  final DateTime month;
  final DateTime today;
  final DateTime selected;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onPick;
  final List<Color> Function(DateTime day) dotsFor;
  final bool Function(DateTime day) isFestival;

  static const _weekHeader = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  Widget build(BuildContext context) {
    // Weeks start on Sunday, like most Indian wall calendars.
    final first = DateTime(month.year, month.month);
    final start = first.subtract(Duration(days: first.weekday % 7));
    final days = [
      for (var i = 0; i < 42; i++)
        DateTime(start.year, start.month, start.day + i),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120E1B4D),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('calendar-prev'),
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left_rounded, color: calPurple),
              ),
              Expanded(
                child: Text(
                  '${monthNames[month.month - 1]} ${month.year}',
                  key: const Key('calendar-month'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: calInk,
                  ),
                ),
              ),
              IconButton(
                key: const Key('calendar-next'),
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right_rounded, color: calPurple),
              ),
            ],
          ),
          Row(
            children: [
              for (final name in _weekHeader)
                Expanded(
                  child: Center(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: name == 'Sun' ? calRed : calBody,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var week = 0; week < 6; week++)
            Row(
              children: [
                for (final day in days.sublist(week * 7, week * 7 + 7))
                  Expanded(
                    child: _DayCell(
                      day: day,
                      inMonth: day.month == month.month,
                      isToday: isSameDay(day, today),
                      isSelected: isSameDay(day, selected),
                      festival: isFestival(day),
                      dots: dotsFor(day),
                      onTap: () => onPick(day),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.festival,
    required this.dots,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final bool festival;
  final List<Color> dots;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color numberColor;
    if (isSelected) {
      numberColor = Colors.white;
    } else if (!inMonth) {
      numberColor = const Color(0xFFB9B5C9);
    } else if (festival) {
      numberColor = festivalColor;
    } else if (day.weekday == DateTime.sunday) {
      numberColor = calRed;
    } else {
      numberColor = calInk;
    }
    return InkWell(
      key: Key('calendar-day-${dateKey(day)}'),
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? calPurple : Colors.transparent,
                shape: BoxShape.circle,
                border: isToday && !isSelected
                    ? Border.all(color: calPurple, width: 2)
                    : null,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: isToday || isSelected
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: numberColor,
                ),
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final color in dots.take(4))
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: inMonth ? color : color.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FestivalCard extends StatelessWidget {
  const _FestivalCard({required this.festival});

  final Festival festival;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD8A8)),
      ),
      child: Row(
        children: [
          const Text('🎉', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              festival.name,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: calInk,
              ),
            ),
          ),
          Text(
            festival.telugu ? 'Telugu' : 'All India',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: festivalColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onTap});

  final CalendarEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(event.category);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: Key('calendar-event-${event.id}'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border(left: BorderSide(color: color, width: 5)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 78,
                  child: Text(
                    event.minuteOfDay == null
                        ? 'All day'
                        : timeLabel(event.minuteOfDay!),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: calInk,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            categoryIcon(event.category),
                            size: 14,
                            color: color,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            event.category.label,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: calBody,
                            ),
                          ),
                          if (event.repeat != Repeat.none) ...[
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.repeat_rounded,
                              size: 14,
                              color: calBody,
                            ),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                event.repeat.label,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  color: calBody,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (event.remindMinutes != null)
                  const Icon(
                    Icons.notifications_active_outlined,
                    size: 18,
                    color: calBody,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown while something stops reminders from ringing on time.
class _OnTimeCard extends StatelessWidget {
  const _OnTimeCard({required this.problem, required this.onFix});

  final ReminderProblem problem;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Material(
      color: const Color(0xFFFFF4E6),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('calendar-on-time'),
        onTap: onFix,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.alarm_rounded, size: 20, color: festivalColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  problem == ReminderProblem.notificationsOff
                      ? 'Notifications are off: reminders cannot ring'
                      : 'Make reminders ring on time',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: calInk,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: calPurple),
            ],
          ),
        ),
      ),
    ),
  );
}

class _OnTimeSheet extends StatelessWidget {
  const _OnTimeSheet({required this.problem});

  final ReminderProblem problem;

  @override
  Widget build(BuildContext context) {
    const text = TextStyle(fontFamily: 'Poppins', fontSize: 14, height: 1.5, color: calInk);
    final off = problem == ReminderProblem.notificationsOff;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Make reminders ring on time',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700, color: calInk),
            ),
            const SizedBox(height: 10),
            Text(
              off
                  ? '1. Open settings, tap Notifications and allow them.'
                  : '1. Allow "Alarms & reminders" for QBOX on the next page. Without it, Android may ring up to an hour late.',
              style: text,
            ),
            const SizedBox(height: 8),
            const Text(
              '2. If reminders still do not ring: open settings, tap Battery, and allow background activity (Unrestricted). '
              'On OPPO, realme, vivo and Xiaomi phones also turn on Auto launch.',
              style: text,
            ),
            const SizedBox(height: 16),
            if (!off)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('on-time-allow'),
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(backgroundColor: calPurple),
                  child: const Text('Allow'),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                key: const Key('on-time-settings'),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Open QBOX settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListeningBar extends StatelessWidget {
  const _ListeningBar({required this.heard, required this.open});

  final String heard;
  final bool open;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('calendar-listening'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: calSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCCBFF)),
      ),
      child: Row(
        children: [
          const Icon(Icons.graphic_eq_rounded, color: calPurple, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  !open
                      ? 'Getting ready…'
                      : heard.isEmpty
                      ? 'Speak now'
                      : heard == '…'
                      ? 'Working it out…'
                      : 'Listening…',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    color: calPurple,
                  ),
                ),
                Text(
                  heard.isEmpty
                      ? 'Say: "remind me tomorrow 10 am supplier payment"'
                      : heard,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: heard.isEmpty ? 13 : 16,
                    fontWeight: heard.isEmpty
                        ? FontWeight.w500
                        : FontWeight.w700,
                    color: heard.isEmpty ? calBody : calInk,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.listening,
    required this.micOpen,
    required this.onSpeak,
    required this.onAdd,
  });

  final bool listening;
  final bool micOpen;
  final VoidCallback onSpeak;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final speakColor = listening ? calRed : calPurple;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      color: calBackground,
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 54,
              child: OutlinedButton.icon(
                key: const Key('calendar-speak'),
                onPressed: onSpeak,
                icon: Icon(listening ? Icons.graphic_eq_rounded : Icons.mic_rounded),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    !listening
                        ? 'Speak'
                        : micOpen
                        ? 'Listening…'
                        : 'Getting ready…',
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: speakColor,
                  backgroundColor: listening
                      ? const Color(0xFFFFE9EB)
                      : calSoft,
                  side: BorderSide(color: speakColor, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 54,
              child: FilledButton.icon(
                key: const Key('calendar-add'),
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add'),
                style: FilledButton.styleFrom(
                  backgroundColor: calPurple,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFF4B12B8), width: 2),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
