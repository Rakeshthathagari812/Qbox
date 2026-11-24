import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/api_client.dart';
import '../udhaar/udhaar_models.dart' show newClientRef;
import 'page_models.dart';

/// The customer's lists and notes on the server. Needs login.
abstract class PagesApi {
  Future<List<QboxPage>> all();

  /// [baseVersion] = the server version this was changed from. Throws a 409
  /// [ApiException] if the server has a newer one.
  Future<QboxPage> save(QboxPage page, {required int baseVersion, required String saveRef});

  Future<void> remove(String ref);
}

class HttpPagesApi implements PagesApi {
  HttpPagesApi(this._api);

  final ApiClient _api;

  static const _base = '/api/customer/pages';
  static const _bad = ApiException('ERROR', 'Something went wrong. Please try again.');

  @override
  Future<List<QboxPage>> all() async {
    final json = await _api.get(_base);
    final pages = json is Map<String, dynamic> ? json['pages'] : null;
    if (pages is! List) throw _bad;
    return pages.map(QboxPage.fromJson).whereType<QboxPage>().toList();
  }

  @override
  Future<QboxPage> save(QboxPage page, {required int baseVersion, required String saveRef}) async {
    final saved = QboxPage.fromJson(
      await _api.put('$_base/${page.ref}', {
        'kind': page.isList ? 'LIST' : 'NOTE',
        'title': page.title,
        'text': page.text,
        'items': [for (final i in page.items) i.toJson()],
        'pinned': page.pinned,
        'baseVersion': baseVersion,
        'saveRef': saveRef,
      }),
    );
    if (saved == null) throw _bad;
    return saved;
  }

  @override
  Future<void> remove(String ref) => _api.delete('$_base/$ref');
}

/// A page on this phone: how it looks here, and the server's copy it came from.
class LocalPage {
  const LocalPage({required this.page, this.base, this.deleted = false, this.sent = const []});

  final QboxPage page;

  /// Null = never saved on the server.
  final QboxPage? base;

  /// Deleted here, and the server does not know yet.
  final bool deleted;

  /// Saves sent whose answer never came: if the server has one of them, it is
  /// this phone's own change and not another phone's.
  final List<String> sent;

  bool get waiting => deleted || base == null || !page.sameContent(base!);

  Map<String, dynamic> toJson() => {
    'page': page.toJson(),
    'base': base?.toJson(),
    'deleted': deleted,
    'sent': sent,
  };

  static LocalPage? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final page = QboxPage.fromJson(json['page']);
    if (page == null) return null;
    final sent = json['sent'];
    return LocalPage(
      page: page,
      base: QboxPage.fromJson(json['base']),
      deleted: json['deleted'] == true,
      sent: sent is List ? sent.whereType<String>().toList() : const [],
    );
  }
}

/// Everything kept on this phone. Cleared on log out.
abstract class PagesStore {
  Future<List<LocalPage>> load();

  Future<void> save(LocalPage page);

  Future<void> remove(String ref);

  Future<void> clear();
}

/// Encrypted with a key in the phone's secure hardware, like the udhaar book.
class SecurePagesStore implements PagesStore {
  SecurePagesStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _prefix = 'qbox_pages_';

  @override
  Future<List<LocalPage>> load() async {
    final out = <LocalPage>[];
    try {
      final all = await _storage.readAll();
      for (final entry in all.entries.where((e) => e.key.startsWith(_prefix))) {
        try {
          final page = LocalPage.fromJson(jsonDecode(entry.value));
          if (page != null) out.add(page);
        } catch (_) {
          // One damaged copy: the server's replaces it.
        }
      }
    } catch (_) {
      // Storage unreadable: the server's copies replace it.
    }
    return out;
  }

  @override
  Future<void> save(LocalPage page) => _storage.write(key: '$_prefix${page.page.ref}', value: jsonEncode(page.toJson()));

  @override
  Future<void> remove(String ref) => _storage.delete(key: '$_prefix$ref');

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
}

/// In memory only. Used by tests.
class MemoryPagesStore implements PagesStore {
  final Map<String, Map<String, dynamic>> saved = {};

  @override
  Future<List<LocalPage>> load() async => [for (final json in saved.values) LocalPage.fromJson(json)!];

  @override
  Future<void> save(LocalPage page) async =>
      saved[page.page.ref] = jsonDecode(jsonEncode(page.toJson())) as Map<String, dynamic>;

  @override
  Future<void> remove(String ref) async => saved.remove(ref);

  @override
  Future<void> clear() async => saved.clear();
}

/// Lists and notes for the screens. Every change is kept on the phone at once,
/// then sent; with no internet it is sent the next time. Screens listen to this.
class PagesRepository extends ChangeNotifier {
  PagesRepository(this.api, this.store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final PagesApi api;
  final PagesStore store;
  final DateTime Function() _now;

  Map<String, LocalPage> _pages = {};
  Future<void>? _loading;
  Future<void>? _running;
  Future<void> _writing = Future.value();
  bool _again = false;
  bool _fetchWanted = false;

  /// Changes on log out, so work still running for the last user is dropped.
  int _user = 0;

  bool ready = false;
  bool offline = false;

  /// The last answer that was not "no internet" (e.g. too many notes).
  String? problem;

  bool get busy => _running != null;

  /// True when something is kept only on this phone.
  bool get waiting => _pages.values.any((p) => p.waiting);

  Future<int> pendingCount() async {
    await (_loading ??= _load());
    return _pages.values.where((p) => p.waiting).length;
  }

  List<QboxPage> get pages => sortPages([
    for (final p in _pages.values)
      if (!p.deleted) p.page,
  ]);

  QboxPage? page(String ref) {
    final local = _pages[ref];
    return local == null || local.deleted ? null : local.page;
  }

  /// The phone's copy, then the server's.
  Future<void> open() async {
    final user = _user;
    await (_loading ??= _load());
    if (user != _user) return;
    notifyListeners();
    await refresh();
  }

  Future<void> _load() async {
    final user = _user;
    final saved = await store.load();
    if (user != _user) return;
    // Anything changed while loading is newer.
    _pages = {for (final p in saved) p.page.ref: p, ..._pages};
    ready = true;
  }

  Future<void> refresh() {
    _fetchWanted = true;
    return _sync();
  }

  /// A new page, or one changed on this phone.
  void put(QboxPage page) {
    final old = _pages[page.ref];
    if (old != null && !old.deleted && old.page.sameContent(page)) return;
    _set(LocalPage(page: page.copyWith(updatedAt: _now()), base: old?.base, sent: old?.sent ?? const []));
    unawaited(_sync());
  }

  /// Changes the page as it is now (another phone's changes may have come in).
  void update(String ref, QboxPage Function(QboxPage page) change) {
    final now = page(ref);
    if (now != null) put(change(now));
  }

  void remove(String ref) {
    final old = _pages[ref];
    if (old == null) return;
    if (old.base == null && old.sent.isEmpty) {
      _drop(ref);
    } else {
      _set(LocalPage(page: old.page, base: old.base, deleted: true, sent: old.sent));
      unawaited(_sync());
    }
  }

  /// Undo of [remove]: it comes back as a new page (the server's is gone).
  void restore(QboxPage page) => put(page.copyWith(ref: newClientRef(), version: 0));

  /// Log out: forget everything.
  Future<void> clear() async {
    _user++;
    _pages = {};
    _loading = null;
    _running = null;
    ready = false;
    offline = false;
    problem = null;
    await _writing;
    await store.clear();
  }

  // ---------- phone copy ----------

  void _set(LocalPage page, {bool tell = true}) {
    _pages[page.page.ref] = page;
    final user = _user;
    _write(() => user == _user ? store.save(page) : Future.value());
    if (tell) notifyListeners();
  }

  void _drop(String ref, {bool tell = true}) {
    _pages.remove(ref);
    final user = _user;
    _write(() => user == _user ? store.remove(ref) : Future.value());
    if (tell) notifyListeners();
  }

  /// One write at a time, in order: an older copy never replaces a newer one.
  void _write(Future<void> Function() write) {
    _writing = _writing.then((_) => write()).catchError((Object _) {});
  }

  // ---------- server ----------

  Future<void> _sync() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    late final Future<void> mine;
    mine = _loop(_user).whenComplete(() {
      if (identical(_running, mine)) {
        _running = null;
        notifyListeners();
      }
    });
    _running = mine;
    return mine;
  }

  Future<void> _loop(int user) async {
    await (_loading ??= _load());
    if (user != _user) return;
    problem = null;
    try {
      do {
        _again = false;
        for (final ref in _pages.keys.toList()) {
          if ((_pages[ref]?.waiting ?? false) && !await _send(ref, user)) return;
        }
        if (_fetchWanted) {
          _fetchWanted = false;
          final fresh = await api.all();
          if (user != _user) return;
          _take(fresh);
        }
        offline = false;
      } while (_again);
    } on ApiException catch (e) {
      if (user != _user) return;
      if (e.isNetwork) {
        offline = true;
      } else {
        problem = e.isUnauthorized ? 'Your session has ended. Please log in again.' : e.message;
      }
      notifyListeners();
    }
  }

  /// The server's pages. One changed on this phone stays until it is sent.
  void _take(List<QboxPage> fresh) {
    final refs = {for (final p in fresh) p.ref};
    for (final p in fresh) {
      final local = _pages[p.ref];
      if (local != null && (local.waiting || local.base?.version == p.version)) continue;
      _set(LocalPage(page: p, base: p), tell: false);
    }
    for (final ref in _pages.keys.toList()) {
      if (!refs.contains(ref) && !_pages[ref]!.waiting) _drop(ref, tell: false);
    }
    notifyListeners();
  }

  /// False = the user logged out meanwhile. Throws [ApiException] for trouble
  /// that also stops the other pages; a page the server refuses stays here.
  Future<bool> _send(String ref, int user) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final local = _pages[ref];
      if (local == null || !local.waiting) return true;
      if (local.deleted) {
        await api.remove(ref);
        if (user != _user) return false;
        if (_pages[ref]?.deleted ?? false) _drop(ref);
        return true;
      }
      final saveRef = newClientRef();
      final sent = [...local.sent, saveRef];
      _set(
        LocalPage(page: local.page, base: local.base, sent: sent.length > 50 ? sent.sublist(sent.length - 50) : sent),
        tell: false,
      );
      // On the phone before it is sent, so it is known again after a restart.
      await _writing;
      try {
        final saved = await api.save(local.page, baseVersion: local.base?.version ?? 0, saveRef: saveRef);
        if (user != _user) return false;
        final now = _pages[ref]!;
        // Changed again while it was being sent: that goes next.
        _set(
          LocalPage(
            page: now.page.sameContent(local.page) ? saved : now.page,
            base: saved,
            deleted: now.deleted,
          ),
        );
      } on ApiException catch (e) {
        if (user != _user) return false;
        if (e.status == 400) {
          problem = '${local.page.name}: ${e.message}';
          return true;
        }
        if (e.status != 409) rethrow;
        if (!await _join(ref, user)) return false;
      }
    }
    return true;
  }

  /// The server has a newer copy (or none): join it with this phone's.
  Future<bool> _join(String ref, int user) async {
    final fresh = await api.all();
    if (user != _user) return false;
    final local = _pages[ref];
    if (local == null || local.deleted) return true;
    final theirs = fresh.where((p) => p.ref == ref).firstOrNull;
    if (theirs == null) {
      // Deleted on another phone, changed on this one: kept as a new page.
      _drop(ref, tell: false);
      _set(LocalPage(page: local.page.copyWith(ref: newClientRef(), version: 0)));
      _again = true;
    } else if (local.sent.contains(theirs.saveRef)) {
      _set(LocalPage(page: local.page, base: theirs));
    } else {
      _set(LocalPage(page: joinPages(local.base, local.page, theirs), base: theirs));
    }
    return true;
  }
}
