import 'package:flutter/material.dart' show IconData, Icons, Color;

import '../calendar/calendar_models.dart' show isSameDay, monthNames;
import '../udhaar/udhaar_models.dart' show EntryKind, newClientRef;

/// Every udhaar line is [paid] (done). A UPI payment waits for the shop's answer.
enum TransactionStatus {
  paid('PAID'),
  waiting('WAITING'),
  notConfirmed('NOT_CONFIRMED');

  const TransactionStatus(this.code);

  final String code;

  static TransactionStatus fromCode(Object? code) =>
      values.firstWhere((s) => s.code == code, orElse: () => TransactionStatus.paid);
}

/// Where the money went. Matches ExpenseCategory on the server.
enum ExpenseCategory {
  groceries('GROCERIES', 'Groceries', Icons.shopping_basket_outlined, Color(0xFF2B8A3E)),
  food('FOOD', 'Food', Icons.restaurant_rounded, Color(0xFFE67700)),
  travel('TRAVEL', 'Travel', Icons.directions_bus_rounded, Color(0xFF1971C2)),
  bills('BILLS', 'Bills', Icons.receipt_long_rounded, Color(0xFF862E9C)),
  health('HEALTH', 'Health', Icons.medical_services_outlined, Color(0xFFD93B4A)),
  education('EDUCATION', 'Education', Icons.school_outlined, Color(0xFF364FC7)),
  clothes('CLOTHES', 'Clothes', Icons.checkroom_rounded, Color(0xFFC2255C)),
  home('HOME', 'Home', Icons.chair_outlined, Color(0xFF5F3DC4)),
  fun('FUN', 'Fun', Icons.movie_outlined, Color(0xFF0B7285)),
  family('FAMILY', 'Family and friends', Icons.people_alt_outlined, Color(0xFF9C5B00)),
  other('OTHER', 'Other', Icons.category_outlined, Color(0xFF5C5872));

  const ExpenseCategory(this.code, this.label, this.icon, this.color);

  final String code;
  final String label;
  final IconData icon;
  final Color color;

  static ExpenseCategory? fromCode(Object? code) {
    for (final c in values) {
      if (c.code == code) return c;
    }
    return null;
  }
}

/// One line of the customer's history: udhaar taken, or money paid.
class Transaction {
  const Transaction({
    required this.id,
    required this.kind,
    required this.amountPaise,
    required this.at,
    required this.shopKey,
    required this.shopName,
    this.bookId,
    this.note,
    this.online = false,
    this.testMode = false,
    this.status = TransactionStatus.paid,
    this.deletedAt,
    this.deleteReason,
    this.own = false,
    this.scanned = false,
    this.upiId,
    this.notSame = false,
    this.same = false,
    this.category,
    this.hidden = false,
    this.pending = false,
  });

  /// The key shared by everything the customer added.
  static const ownKey = 'own';

  final String id;
  final EntryKind kind;
  final int amountPaise;
  final DateTime at;

  /// The same for everything at one shop ([ownKey] for what they added).
  final String shopKey;
  final String shopName;
  final int? bookId;
  final String? note;

  /// Paid from QBOX: money moved, even if the shop later deletes the line.
  final bool online;
  final bool testMode;
  final TransactionStatus status;
  final DateTime? deletedAt;
  final String? deleteReason;

  /// Added by the customer; QBOX cannot confirm it.
  final bool own;
  final bool scanned;
  final String? upiId;

  /// They said it is not the same payment as another one that day.
  final bool notSame;

  /// They said it is: shown, but not counted.
  final bool same;

  /// Payments only: udhaar taken counts as spending when it is paid.
  final ExpenseCategory? category;

  /// Left out of Expenses by the customer.
  final bool hidden;

  /// Saved on the phone, waiting for internet.
  final bool pending;

  bool get deleted => deletedAt != null;

  /// Counted in the totals.
  bool get counts => status == TransactionStatus.paid && (!deleted || online) && !same;

  /// Money spent (counted once: udhaar when it is paid).
  bool get isExpense => kind == EntryKind.payment && counts;

  /// The number of a record the customer added ("own-7" -> 7).
  int? get recordId => own && !pending ? int.tryParse(id.split('-').last) : null;

  static Transaction? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final kind = EntryKind.fromCode(json['kind']);
    final amount = json['amountPaise'];
    final at = _time(json['at']);
    final shopKey = json['shopKey'];
    final shopName = json['shopName'];
    if (id is! String || kind == null || amount is! int || at == null || shopKey is! String || shopName is! String) {
      return null;
    }
    return Transaction(
      id: id,
      kind: kind,
      amountPaise: amount,
      at: at,
      shopKey: shopKey,
      shopName: shopName,
      bookId: json['bookId'] as int?,
      note: json['note'] as String?,
      online: json['online'] == true,
      testMode: json['testMode'] == true,
      status: TransactionStatus.fromCode(json['status']),
      deletedAt: _time(json['deletedAt']),
      deleteReason: json['deleteReason'] as String?,
      own: json['own'] == true,
      scanned: json['scanned'] == true,
      upiId: json['upiId'] as String?,
      notSame: json['notSame'] == true,
      same: json['same'] == true,
      category: ExpenseCategory.fromCode(json['category']),
      hidden: json['hidden'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.code,
    'amountPaise': amountPaise,
    'at': at.toUtc().toIso8601String(),
    'shopKey': shopKey,
    'shopName': shopName,
    'bookId': bookId,
    'note': note,
    'online': online,
    'testMode': testMode,
    'status': status.code,
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
    'deleteReason': deleteReason,
    'own': own,
    'scanned': scanned,
    'upiId': upiId,
    'notSame': notSame,
    'same': same,
    'category': category?.code,
    'hidden': hidden,
  };
}

/// One month of history, newest first.
class MonthHistory {
  const MonthHistory({required this.month, required this.months, required this.items, this.budgetPaise});

  /// "2026-11".
  final String month;

  /// Every month that has something, newest first.
  final List<String> months;
  final List<Transaction> items;

  /// What they want to spend in a month.
  final int? budgetPaise;

  static MonthHistory? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final month = json['month'];
    final months = json['months'];
    final items = json['transactions'];
    if (month is! String || months is! List || items is! List) return null;
    return MonthHistory(
      month: month,
      months: months.whereType<String>().toList(),
      items: items.map(Transaction.fromJson).whereType<Transaction>().toList(),
      budgetPaise: json['budgetPaise'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'month': month,
    'months': months,
    'transactions': [for (final t in items) t.toJson()],
    'budgetPaise': budgetPaise,
  };

  /// With the records still waiting on this phone.
  MonthHistory withPending(List<RecordDraft> pending) {
    if (pending.isEmpty) return this;
    final mine = pending.where((d) => monthKey(d.at) == month).map((d) => d.asPending());
    return MonthHistory(
      month: month,
      months: ({...months, for (final d in pending) monthKey(d.at)}.toList()..sort()).reversed.toList(),
      items: [...items, ...mine]..sort((a, b) => b.at.compareTo(a.at)),
      budgetPaise: budgetPaise,
    );
  }
}

/// A payment the customer adds. [clientRef] is made on the phone, so sending it
/// twice (after being offline) keeps one.
class RecordDraft {
  RecordDraft({
    required this.title,
    required this.amountPaise,
    required this.category,
    required this.at,
    this.note = '',
    this.scanned = false,
    this.upiId,
    String? clientRef,
  }) : clientRef = clientRef ?? newClientRef();

  final String title;
  final int amountPaise;
  final ExpenseCategory category;
  final DateTime at;
  final String note;
  final bool scanned;
  final String? upiId;
  final String clientRef;

  Map<String, dynamic> toJson() => {
    'title': title,
    'amountPaise': amountPaise,
    'category': category.code,
    'spentAt': at.toUtc().toIso8601String(),
    'note': note.trim().isEmpty ? null : note.trim(),
    'scanned': scanned,
    'upiId': upiId,
    'clientRef': clientRef,
  };

  static RecordDraft? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final title = json['title'];
    final amount = json['amountPaise'];
    final at = _time(json['spentAt']);
    final ref = json['clientRef'];
    if (title is! String || amount is! int || at == null || ref is! String) return null;
    return RecordDraft(
      title: title,
      amountPaise: amount,
      category: ExpenseCategory.fromCode(json['category']) ?? ExpenseCategory.other,
      at: at,
      note: json['note'] as String? ?? '',
      scanned: json['scanned'] == true,
      upiId: json['upiId'] as String?,
      clientRef: ref,
    );
  }

  Transaction asPending() => Transaction(
    id: 'pending-$clientRef',
    kind: EntryKind.payment,
    amountPaise: amountPaise,
    at: at,
    shopKey: Transaction.ownKey,
    shopName: title,
    note: note.trim().isEmpty ? null : note.trim(),
    own: true,
    scanned: scanned,
    upiId: upiId,
    category: category,
    pending: true,
  );
}

/// "Did the payment go through?" for a scanned QR, kept until it is answered.
class ScanQuestion {
  ScanQuestion({required this.title, required this.at, this.upiId, this.amountPaise, String? clientRef})
    : clientRef = clientRef ?? newClientRef();

  final String title;
  final DateTime at;
  final String? upiId;

  /// Null when the amount was typed in the other app.
  final int? amountPaise;

  /// Becomes the record's id, so answering twice adds it once.
  final String clientRef;

  Map<String, dynamic> toJson() => {
    'title': title,
    'at': at.toUtc().toIso8601String(),
    'upiId': upiId,
    'amountPaise': amountPaise,
    'clientRef': clientRef,
  };

  static ScanQuestion? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final title = json['title'];
    final at = _time(json['at']);
    final ref = json['clientRef'];
    if (title is! String || at == null || ref is! String) return null;
    return ScanQuestion(
      title: title,
      at: at,
      upiId: json['upiId'] as String?,
      amountPaise: json['amountPaise'] as int?,
      clientRef: ref,
    );
  }
}

int totalTaken(Iterable<Transaction> items) =>
    items.where((t) => t.counts && t.kind == EntryKind.credit).fold(0, (sum, t) => sum + t.amountPaise);

int totalPaid(Iterable<Transaction> items) =>
    items.where((t) => t.isExpense).fold(0, (sum, t) => sum + t.amountPaise);

/// The part of [totalPaid] that QBOX cannot confirm.
int totalOwn(Iterable<Transaction> items) => totalPaid(items.where((t) => t.own));

/// What is counted as spent: payments, without the ones left out.
int totalSpent(Iterable<Transaction> items) => totalPaid(items.where((t) => !t.hidden));

/// Spending per category, biggest first.
List<(ExpenseCategory, int)> spentByCategory(Iterable<Transaction> items) {
  final sums = <ExpenseCategory, int>{};
  for (final t in items.where((t) => t.isExpense && !t.hidden)) {
    final c = t.category ?? ExpenseCategory.other;
    sums[c] = (sums[c] ?? 0) + t.amountPaise;
  }
  return sums.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
}

/// Added records that may be the same payment as one QBOX already has (same
/// amount, same day): record id -> the other one. Each other one is used once.
Map<String, Transaction> possibleDuplicates(List<Transaction> items) {
  final known = items
      .where((t) => !t.own && !t.deleted && t.kind == EntryKind.payment && t.status != TransactionStatus.notConfirmed)
      .toList();
  int match(Transaction t) => known.indexWhere((k) => k.amountPaise == t.amountPaise && isSameDay(k.at, t.at));
  // Ones already answered use up theirs first.
  for (final t in items.where((t) => t.same)) {
    final i = match(t);
    if (i >= 0) known.removeAt(i);
  }
  final result = <String, Transaction>{};
  for (final t in items.where((t) => t.own && !t.notSame && !t.same && !t.pending)) {
    final i = match(t);
    if (i >= 0) result[t.id] = known.removeAt(i);
  }
  return result;
}

/// "2026-11" for any day in November 2026.
String monthKey(DateTime day) => '${day.year}-${day.month.toString().padLeft(2, '0')}';

/// "2026-11" -> "November 2026".
String monthLabel(String key) {
  final number = int.tryParse(key.length >= 7 ? key.substring(5, 7) : '') ?? 0;
  return number < 1 || number > 12 ? key : '${monthNames[number - 1]} ${key.substring(0, 4)}';
}

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
