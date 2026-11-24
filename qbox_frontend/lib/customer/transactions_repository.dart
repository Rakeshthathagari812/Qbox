import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/api_client.dart';
import 'transaction_models.dart';

/// The customer's own history and expenses. Needs login.
abstract class TransactionsApi {
  Future<MonthHistory> month(String month);

  Future<void> addRecord(RecordDraft draft);

  /// The same payment as another one of that day (kept, not counted).
  Future<void> sameRecord(int id);

  /// Not the same: counted, and not asked again.
  Future<void> differentRecord(int id);

  /// An expense: its category (null = the usual one), or left out.
  Future<void> mark(String itemId, {ExpenseCategory? category, required bool hidden});

  Future<void> setBudget(int? monthPaise);
}

class HttpTransactionsApi implements TransactionsApi {
  HttpTransactionsApi(this._api);

  final ApiClient _api;

  static const _base = '/api/customer';

  @override
  Future<MonthHistory> month(String month) async {
    final history = MonthHistory.fromJson(
      // Payments still being checked are looked up at Razorpay.
      await _api.get('$_base/transactions?month=$month', timeout: const Duration(seconds: 30)),
    );
    if (history == null) throw const ApiException('ERROR', 'Something went wrong. Please try again.');
    return history;
  }

  @override
  Future<void> addRecord(RecordDraft draft) => _api.post('$_base/records', draft.toJson());

  @override
  Future<void> sameRecord(int id) => _api.post('$_base/records/$id/same', {});

  @override
  Future<void> differentRecord(int id) => _api.post('$_base/records/$id/different', {});

  @override
  Future<void> mark(String itemId, {ExpenseCategory? category, required bool hidden}) =>
      _api.put('$_base/expenses/$itemId', {'category': category?.code, 'hidden': hidden});

  @override
  Future<void> setBudget(int? monthPaise) => _api.put('$_base/budget', {'monthPaise': monthPaise});
}

/// The months already seen, records waiting for internet, and unanswered
/// "did it go through?" questions. Cleared on log out.
abstract class TransactionsStore {
  Future<MonthHistory?> load(String month);

  Future<void> save(MonthHistory history);

  Future<List<RecordDraft>> loadPending();

  Future<void> savePending(List<RecordDraft> pending);

  Future<List<ScanQuestion>> loadQuestions();

  Future<void> saveQuestions(List<ScanQuestion> questions);

  Future<void> clear();
}

/// Encrypted with a key in the phone's secure hardware, like the udhaar book.
class SecureTransactionsStore implements TransactionsStore {
  SecureTransactionsStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _prefix = 'qbox_transactions_';

  @override
  Future<MonthHistory?> load(String month) async => MonthHistory.fromJson(await _read(month));

  @override
  Future<void> save(MonthHistory history) => _write(history.month, history.toJson());

  @override
  Future<List<RecordDraft>> loadPending() async {
    final data = await _read('pending');
    return data is List ? data.map(RecordDraft.fromJson).whereType<RecordDraft>().toList() : <RecordDraft>[];
  }

  @override
  Future<void> savePending(List<RecordDraft> pending) => _write('pending', [for (final p in pending) p.toJson()]);

  @override
  Future<List<ScanQuestion>> loadQuestions() async {
    final data = await _read('questions');
    return data is List ? data.map(ScanQuestion.fromJson).whereType<ScanQuestion>().toList() : <ScanQuestion>[];
  }

  @override
  Future<void> saveQuestions(List<ScanQuestion> questions) =>
      _write('questions', [for (final q in questions) q.toJson()]);

  @override
  Future<void> clear() async {
    try {
      final all = await _storage.readAll();
      for (final key in all.keys.where((k) => k.startsWith(_prefix))) {
        await _storage.delete(key: key);
      }
    } catch (_) {
      // Storage unreadable: nothing that can be read is left.
    }
  }

  Future<Object?> _read(String key) async {
    try {
      final text = await _storage.read(key: '$_prefix$key');
      return text == null ? null : jsonDecode(text);
    } catch (_) {
      return null; // damaged copy: the next sync replaces it
    }
  }

  Future<void> _write(String key, Object value) => _storage.write(key: '$_prefix$key', value: jsonEncode(value));
}

/// In memory only. Used by tests.
class MemoryTransactionsStore implements TransactionsStore {
  final Map<String, MonthHistory> saved = {};
  List<RecordDraft> pending = [];
  List<ScanQuestion> questions = [];

  @override
  Future<MonthHistory?> load(String month) async => saved[month];

  @override
  Future<void> save(MonthHistory history) async => saved[history.month] = history;

  @override
  Future<List<RecordDraft>> loadPending() async => List.of(pending);

  @override
  Future<void> savePending(List<RecordDraft> list) async => pending = List.of(list);

  @override
  Future<List<ScanQuestion>> loadQuestions() async => List.of(questions);

  @override
  Future<void> saveQuestions(List<ScanQuestion> list) async => questions = List.of(list);

  @override
  Future<void> clear() async {
    saved.clear();
    pending = [];
    questions = [];
  }
}

/// The customer's history for the screens: the server, the phone copy, and the
/// records added while offline.
class TransactionsRepository {
  TransactionsRepository(this.api, this.store);

  final TransactionsApi api;
  final TransactionsStore store;

  Future<List<String>>? _sending;

  /// The phone copy, with records waiting for internet. Null if there is neither.
  Future<MonthHistory?> saved(String month) async {
    final pending = await store.loadPending();
    final history = await store.load(month);
    if (history == null && !pending.any((d) => monthKey(d.at) == month)) return null;
    return (history ?? MonthHistory(month: month, months: const [], items: const [])).withPending(pending);
  }

  /// Throws [ApiException] (e.g. no internet).
  Future<MonthHistory> fresh(String month) async {
    await sendPending();
    final history = await api.month(month);
    await store.save(history);
    return history.withPending(await store.loadPending());
  }

  /// True = on the server; false = kept on the phone until there is internet.
  Future<bool> addRecord(RecordDraft draft) async {
    await sendPending();
    try {
      await api.addRecord(draft);
      return true;
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      final pending = await store.loadPending();
      if (!pending.any((d) => d.clientRef == draft.clientRef)) pending.add(draft);
      await store.savePending(pending);
      return false;
    }
  }

  /// Sends the records saved while offline. Returns what the server refused
  /// (those are dropped).
  Future<List<String>> sendPending() => _sending ??= _send().whenComplete(() => _sending = null);

  Future<List<String>> _send() async {
    final refused = <String>[];
    var pending = await store.loadPending();
    while (pending.isNotEmpty) {
      final next = pending.first;
      try {
        await api.addRecord(next);
      } on ApiException catch (e) {
        // Only a record the server says is wrong is dropped; anything else
        // (no internet, server trouble) stays for next time.
        if (e.status != 400) break;
        refused.add('${next.title}: ${e.message}');
      }
      pending = await store.loadPending()
        ..removeWhere((d) => d.clientRef == next.clientRef);
      await store.savePending(pending);
    }
    return refused;
  }

  // ---------- "did the payment go through?" ----------

  Future<List<ScanQuestion>> questions() => store.loadQuestions();

  Future<void> ask(ScanQuestion question) async =>
      store.saveQuestions([...await store.loadQuestions(), question]);

  /// Yes ([amountPaise] given) adds the payment; no forgets the question.
  Future<void> answer(ScanQuestion question, {int? amountPaise}) async {
    if (amountPaise != null) {
      await addRecord(
        RecordDraft(
          title: question.title,
          amountPaise: amountPaise,
          category: ExpenseCategory.other,
          at: question.at,
          scanned: true,
          upiId: question.upiId,
          clientRef: question.clientRef,
        ),
      );
    }
    final left = await store.loadQuestions()
      ..removeWhere((q) => q.clientRef == question.clientRef);
    await store.saveQuestions(left);
  }

  Future<int> pendingCount() async => (await store.loadPending()).length;

  /// Log out: forget everything.
  Future<void> clear() => store.clear();
}
