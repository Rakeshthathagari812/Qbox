import '../onboarding_draft.dart';
import '../services/api_client.dart';
import '../udhaar/udhaar_models.dart' show newClientRef;
import 'calendar_api.dart';
import 'calendar_models.dart';
import 'calendar_store.dart';
import 'reminders.dart';

/// One change made without internet, to be sent later.
class CalendarChange {
  const CalendarChange({required this.ref, required this.role, required this.eventId, this.draft});

  final String ref;
  final QboxRole role;

  /// Below 0 = added here, not on the server yet.
  final int eventId;

  /// Null = deleted.
  final EventDraft? draft;

  bool get isNew => eventId < 0;

  Map<String, dynamic> toJson() => {
    'ref': ref,
    'role': role.name,
    'event': eventId,
    'draft': draft == null ? null : asEvent(eventId, draft!).toCacheJson(),
  };

  static CalendarChange? fromJson(Object? json) {
    if (json is! Map) return null;
    final ref = json['ref'];
    final id = json['event'];
    final role = QboxRole.values.where((r) => r.name == json['role']).firstOrNull;
    if (ref is! String || id is! int || role == null) return null;
    final draft = json['draft'] == null ? null : CalendarEvent.fromJson(json['draft']);
    if (json['draft'] != null && draft == null) return null;
    return CalendarChange(ref: ref, role: role, eventId: id, draft: draft);
  }
}

CalendarEvent asEvent(int id, EventDraft d) => CalendarEvent(
  id: id,
  title: d.title.trim(),
  day: DateTime(d.day.year, d.day.month, d.day.day),
  minuteOfDay: d.minuteOfDay,
  category: d.category,
  repeat: d.repeat,
  remindMinutes: d.remindMinutes,
  note: d.note.trim(),
);

/// The calendar, also without internet: changes are kept on the phone, shown and
/// reminded of straight away, and sent when the server can be reached.
class CalendarRepository implements CalendarApi {
  CalendarRepository(this._api, this._store, this._reminders);

  final CalendarApi _api;
  final CalendarStore _store;
  final ReminderScheduler _reminders;

  /// One thing at a time, so nothing is sent twice.
  Future<void> _last = Future.value();

  /// Ids given here -> the server's, for a screen that was open meanwhile.
  final Map<int, int> _became = {};

  Future<T> _inTurn<T>(Future<T> Function() work) {
    final mine = _last.then((_) => work());
    _last = mine.then<void>((_) {}, onError: (_) {});
    return mine;
  }

  Future<int> pendingCount() async => (await _store.loadChanges()).length;

  @override
  Future<List<CalendarEvent>> events(QboxRole role) => _inTurn(() async {
    await _send();
    final fresh = await _api.events(role);
    final shown = _with(fresh, await _store.loadChanges(), role);
    await _store.saveEvents(role, shown);
    return shown;
  });

  @override
  Future<List<Festival>> festivals() => _api.festivals();

  @override
  Future<CalendarEvent> create(QboxRole role, EventDraft draft, {String? ref}) => _inTurn(() async {
    final mine = ref ?? newClientRef();
    try {
      await _send();
      return await _saved(role, await _api.create(role, draft, ref: mine));
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      final changes = await _store.loadChanges();
      final lowest = [0, for (final c in changes) c.eventId, ..._became.keys].reduce((a, b) => a < b ? a : b);
      final change = CalendarChange(ref: mine, role: role, eventId: lowest - 1, draft: draft);
      await _keep([...changes, change], change);
      return asEvent(change.eventId, draft);
    }
  });

  @override
  Future<CalendarEvent> update(QboxRole role, int id, EventDraft draft) => _inTurn(() async {
    try {
      await _send();
      final real = _became[id] ?? id;
      if (real >= 0) return await _saved(role, await _api.update(role, real, draft));
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
    }
    final real = _became[id] ?? id;
    await _replace(role, real, draft);
    return asEvent(real, draft);
  });

  @override
  Future<void> delete(int id) => _inTurn(() async {
    try {
      await _send();
      final real = _became[id] ?? id;
      if (real >= 0) {
        await _api.delete(real);
        await _removed(real);
        return;
      }
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
    }
    final real = _became[id] ?? id;
    for (final role in QboxRole.values) {
      final here = await _store.loadEvents(role) ?? const [];
      if (here.any((e) => e.id == real)) return _replace(role, real, null);
    }
  });

  /// Saved on the server: shown and reminded of from here too.
  Future<CalendarEvent> _saved(QboxRole role, CalendarEvent event) async {
    final here = [
      for (final e in await _store.loadEvents(role) ?? const <CalendarEvent>[])
        if (e.id != event.id) e,
      event,
    ];
    await _store.saveEvents(role, here);
    await _reminders.sync(role, here);
    return event;
  }

  Future<void> _removed(int id) async {
    for (final role in QboxRole.values) {
      final here = await _store.loadEvents(role);
      if (here == null || !here.any((e) => e.id == id)) continue;
      final left = [
        for (final e in here)
          if (e.id != id) e,
      ];
      await _store.saveEvents(role, left);
      await _reminders.sync(role, left);
    }
  }

  Future<void> _replace(QboxRole role, int id, EventDraft? draft) async {
    final changes = await _store.loadChanges();
    final at = changes.indexWhere((c) => c.eventId == id);
    final change = CalendarChange(ref: at < 0 ? newClientRef() : changes[at].ref, role: role, eventId: id, draft: draft);
    if (at < 0) {
      changes.add(change);
    } else {
      changes[at] = change;
    }
    // Added and deleted here: the server may still have got it, when only its
    // answer was lost. Then it comes back, and can be deleted again.
    if (id < 0 && draft == null) changes.removeWhere((c) => c.eventId == id);
    await _keep(changes, change);
  }

  Future<void> _keep(List<CalendarChange> changes, CalendarChange change) async {
    await _store.saveChanges(changes);
    final shown = _with(await _store.loadEvents(change.role) ?? const [], [change], change.role);
    await _store.saveEvents(change.role, shown);
    await _reminders.sync(change.role, shown);
  }

  List<CalendarEvent> _with(List<CalendarEvent> events, List<CalendarChange> changes, QboxRole role) {
    final out = List.of(events);
    for (final c in changes.where((c) => c.role == role)) {
      final at = out.indexWhere((e) => e.id == c.eventId);
      final draft = c.draft;
      if (draft == null) {
        out.removeWhere((e) => e.id == c.eventId);
      } else if (at >= 0) {
        out[at] = asEvent(c.eventId, draft);
      } else if (c.isNew) {
        out.add(asEvent(c.eventId, draft));
      }
    }
    return out;
  }

  /// Sends what is waiting. Throws when the server cannot be reached.
  Future<void> _send() async {
    for (final c in await _store.loadChanges()) {
      final draft = c.draft;
      try {
        if (draft == null) {
          await _api.delete(c.eventId);
        } else if (c.isNew) {
          final made = await _api.create(c.role, draft, ref: c.ref);
          _became[c.eventId] = made.id;
          // It had arrived before, and was changed here since.
          if ('${asEvent(0, made).toCacheJson()}' != '${asEvent(0, draft).toCacheJson()}') {
            await _api.update(c.role, made.id, draft);
          }
        } else {
          await _api.update(c.role, c.eventId, draft);
        }
      } on ApiException catch (e) {
        // Not reached, logged out, or the server is in trouble: later.
        if (e.isNetwork || e.isUnauthorized || e.status >= 500) rethrow;
        // Refused. A new one stays here, so it is not lost; a change to one that
        // was deleted on another phone goes.
        if (c.isNew) continue;
      }
      final left = await _store.loadChanges();
      await _store.saveChanges([for (final l in left) if (l.ref != c.ref) l]);
    }
  }

  /// Sets every reminder again: after QBOX was force-stopped the phone forgets
  /// them, and events may have been added on another phone.
  Future<void> remindAgain(Iterable<QboxRole> roles) async {
    for (final role in roles) {
      try {
        final saved = await _store.loadEvents(role);
        if (saved != null) await _reminders.sync(role, saved);
        final fresh = await events(role);
        await _reminders.sync(role, fresh);
      } catch (_) {
        // No internet: the saved ones are set.
      }
    }
  }
}
