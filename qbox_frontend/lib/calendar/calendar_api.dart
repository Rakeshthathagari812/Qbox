import '../models/qbox_user.dart';
import '../onboarding_draft.dart';
import '../services/api_client.dart';
import 'calendar_models.dart';

/// Everything the app asks the backend about the calendar. Needs login.
abstract class CalendarApi {
  Future<List<CalendarEvent>> events(QboxRole role);

  /// The same [ref] sent twice is kept once.
  Future<CalendarEvent> create(QboxRole role, EventDraft draft, {String? ref});

  Future<CalendarEvent> update(QboxRole role, int id, EventDraft draft);

  Future<void> delete(int id);

  Future<List<Festival>> festivals();
}

class HttpCalendarApi implements CalendarApi {
  HttpCalendarApi(this._api);

  final ApiClient _api;

  @override
  Future<List<CalendarEvent>> events(QboxRole role) async {
    final json = await _api.get('/api/calendar/events?role=${roleCode(role)}');
    return _list(json, CalendarEvent.fromJson);
  }

  @override
  Future<CalendarEvent> create(QboxRole role, EventDraft draft, {String? ref}) async {
    return _one(await _api.post('/api/calendar/events', {...draft.toJson(role), 'clientRef': ?ref}));
  }

  @override
  Future<CalendarEvent> update(QboxRole role, int id, EventDraft draft) async {
    return _one(await _api.put('/api/calendar/events/$id', draft.toJson(role)));
  }

  @override
  Future<void> delete(int id) => _api.delete('/api/calendar/events/$id');

  @override
  Future<List<Festival>> festivals() async {
    return _list(await _api.get('/api/calendar/festivals'), Festival.fromJson);
  }

  static List<T> _list<T>(Object? json, T? Function(Object?) read) =>
      json is List ? json.map(read).whereType<T>().toList() : <T>[];

  static CalendarEvent _one(Object? json) {
    final event = CalendarEvent.fromJson(json);
    if (event == null) {
      throw const ApiException(
        'ERROR',
        'Something went wrong. Please try again.',
      );
    }
    return event;
  }
}
