import 'package:qbox_app/customer/transaction_models.dart';
import 'package:qbox_app/customer/transactions_repository.dart';
import 'package:qbox_app/services/api_client.dart';
import 'package:qbox_app/udhaar/udhaar_models.dart' show EntryKind;

/// Pretend history server: give it every line, it answers one month at a time.
class FakeTransactionsApi implements TransactionsApi {
  List<Transaction> all = [];
  bool offline = false;
  int? budget;
  final List<String> calls = [];

  /// Answered to the next change with this error.
  ApiException? nextError;
  int _next = 1;
  final List<String> asked = [];

  @override
  Future<MonthHistory> month(String month) async {
    asked.add(month);
    _check(null);
    return MonthHistory(
      month: month,
      months: ({for (final t in all) monthKey(t.at)}.toList()..sort()).reversed.toList(),
      items: all.where((t) => monthKey(t.at) == month).toList()..sort((a, b) => b.at.compareTo(a.at)),
      budgetPaise: budget,
    );
  }

  void _check(String? call) {
    if (call != null) calls.add(call);
    if (offline) {
      throw const ApiException('NETWORK', 'Cannot reach the QBOX server. Check your internet connection.');
    }
    final error = nextError;
    if (call != null && error != null) {
      nextError = null;
      throw error;
    }
  }

  final Set<String> _refs = {};

  Transaction _own(String id, RecordDraft d) => Transaction(
    id: id,
    kind: EntryKind.payment,
    amountPaise: d.amountPaise,
    at: d.at,
    shopKey: Transaction.ownKey,
    shopName: d.title,
    note: d.note.trim().isEmpty ? null : d.note.trim(),
    own: true,
    scanned: d.scanned,
    upiId: d.upiId,
    category: d.category,
  );

  @override
  Future<void> addRecord(RecordDraft draft) async {
    _check('add ${draft.title} ${draft.amountPaise}');
    if (_refs.add(draft.clientRef)) all.add(_own('own-${_next++}', draft));
  }

  void _answer(int id, {required bool same}) {
    final i = all.indexWhere((t) => t.id == 'own-$id');
    all[i] = Transaction.fromJson({...all[i].toJson(), 'same': same, 'notSame': !same})!;
  }

  @override
  Future<void> sameRecord(int id) async {
    _check('same $id');
    _answer(id, same: true);
  }

  @override
  Future<void> differentRecord(int id) async {
    _check('different $id');
    _answer(id, same: false);
  }

  @override
  Future<void> mark(String itemId, {ExpenseCategory? category, required bool hidden}) async {
    _check('mark $itemId ${category?.code} $hidden');
    final i = all.indexWhere((t) => t.id == itemId);
    all[i] = Transaction.fromJson({...all[i].toJson(), 'category': category?.code, 'hidden': hidden})!;
  }

  @override
  Future<void> setBudget(int? monthPaise) async {
    _check('budget $monthPaise');
    budget = monthPaise;
  }
}
