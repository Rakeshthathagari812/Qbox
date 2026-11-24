import 'package:qbox_app/onboarding_draft.dart';
import 'package:qbox_app/profile/notices.dart';
import 'package:qbox_app/services/api_client.dart';

/// Pretend bell.
class FakeNoticesApi implements NoticesApi {
  Map<QboxRole, List<Notice>> items = {};
  Map<QboxRole, Set<NoticeType>> off = {};
  final List<String> calls = [];
  bool offline = false;

  void _check(String call) {
    calls.add(call);
    if (offline) {
      throw const ApiException('NETWORK', 'Cannot reach the QBOX server. Check your internet connection.');
    }
  }

  @override
  Future<Notices> all(QboxRole role) async {
    _check('all');
    final list = items[role] ?? const [];
    return Notices(unread: list.where((n) => n.unread).length, off: off[role] ?? {}, items: list);
  }

  @override
  Future<int> unread(QboxRole role) async {
    _check('unread ${role.name}');
    return (items[role] ?? const []).where((n) => n.unread).length;
  }

  @override
  Future<void> markRead(QboxRole role, {String? id}) async {
    _check('read ${id ?? 'all'}');
    items[role] = [for (final n in items[role] ?? const <Notice>[]) id == null || n.id == id ? n.read() : n];
  }

  @override
  Future<void> setOff(QboxRole role, Set<NoticeType> types) async {
    _check('off');
    off[role] = types;
  }
}
