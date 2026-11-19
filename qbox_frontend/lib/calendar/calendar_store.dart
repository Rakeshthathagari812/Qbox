import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/qbox_user.dart';
import '../onboarding_draft.dart';
import 'calendar_models.dart';

/// A copy of the calendar on the phone, so it still opens without internet.
/// The server is the real record; this copy is replaced after every sync.
/// Cleared on log out.
abstract class CalendarStore {
  Future<List<CalendarEvent>?> loadEvents(QboxRole role);

  Future<void> saveEvents(QboxRole role, List<CalendarEvent> events);

  Future<List<Festival>?> loadFestivals();

  Future<void> saveFestivals(List<Festival> festivals);

  Future<void> clear();
}

class PrefsCalendarStore implements CalendarStore {
  static const _prefix = 'qbox_calendar_';
  static String _eventsKey(QboxRole role) =>
      '${_prefix}events_${roleCode(role)}';
  static const _festivalsKey = '${_prefix}festivals';

  @override
  Future<List<CalendarEvent>?> loadEvents(QboxRole role) async =>
      _load(_eventsKey(role), CalendarEvent.fromJson);

  @override
  Future<void> saveEvents(QboxRole role, List<CalendarEvent> events) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _eventsKey(role),
      jsonEncode([for (final e in events) e.toCacheJson()]),
    );
  }

  @override
  Future<List<Festival>?> loadFestivals() async =>
      _load(_festivalsKey, Festival.fromJson);

  @override
  Future<void> saveFestivals(List<Festival> festivals) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _festivalsKey,
      jsonEncode([for (final f in festivals) f.toJson()]),
    );
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key
        in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await prefs.remove(key);
    }
  }

  Future<List<T>?> _load<T>(String key, T? Function(Object?) read) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = prefs.getString(key);
      if (text == null) return null;
      final data = jsonDecode(text);
      return data is List ? data.map(read).whereType<T>().toList() : null;
    } catch (_) {
      return null; // damaged copy: the next sync replaces it
    }
  }
}

/// In memory only. Used by tests.
class MemoryCalendarStore implements CalendarStore {
  final Map<QboxRole, List<CalendarEvent>> events = {};
  List<Festival>? festivals;

  @override
  Future<List<CalendarEvent>?> loadEvents(QboxRole role) async => events[role];

  @override
  Future<void> saveEvents(QboxRole role, List<CalendarEvent> list) async =>
      events[role] = List.of(list);

  @override
  Future<List<Festival>?> loadFestivals() async => festivals;

  @override
  Future<void> saveFestivals(List<Festival> list) async =>
      festivals = List.of(list);

  @override
  Future<void> clear() async {
    events.clear();
    festivals = null;
  }
}
