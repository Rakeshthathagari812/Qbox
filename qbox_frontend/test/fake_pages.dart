import 'dart:async';

import 'package:qbox_app/customer/page_models.dart';
import 'package:qbox_app/customer/pages_repository.dart';
import 'package:qbox_app/services/api_client.dart';

/// Pretend lists-and-notes server with the same rules as the FastAPI one.
class FakePagesApi implements PagesApi {
  final Map<String, QboxPage> pages = {};
  final Set<String> deleted = {};
  final List<String> calls = [];
  bool offline = false;

  /// Keeps the save but the answer never arrives.
  bool loseAnswer = false;
  ApiException? refuse;

  /// Waits for this before answering a save.
  Completer<void>? hold;

  static const _network = ApiException('NETWORK', 'Cannot reach the QBOX server. Check your internet connection.');

  @override
  Future<List<QboxPage>> all() async {
    calls.add('all');
    if (offline) throw _network;
    return pages.values.toList();
  }

  @override
  Future<QboxPage> save(QboxPage page, {required int baseVersion, required String saveRef}) async {
    calls.add('save ${page.name} $baseVersion');
    await hold?.future;
    if (offline) throw _network;
    final error = refuse;
    if (error != null) throw error;
    final old = pages[page.ref];
    if (deleted.contains(page.ref) || (old?.version ?? 0) != baseVersion) {
      throw const ApiException('PAGE_CHANGED', 'This was changed on another phone. Please try again', status: 409);
    }
    final saved = keep(page, baseVersion + 1, saveRef);
    if (loseAnswer) {
      loseAnswer = false;
      throw _network;
    }
    return saved;
  }

  /// As if another phone saved it.
  QboxPage keep(QboxPage page, int version, [String saveRef = 'other-phone']) =>
      pages[page.ref] = QboxPage.fromJson({...page.toJson(), 'version': version, 'saveRef': saveRef})!;

  @override
  Future<void> remove(String ref) async {
    calls.add('remove');
    if (offline) throw _network;
    pages.remove(ref);
    deleted.add(ref);
  }
}
