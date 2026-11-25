import 'dart:math';

import '../calendar/calendar_models.dart' show isSameDay, monthNames, timeLabel;

/// Money is always whole paise (₹1 = 100 paise), never decimals, so totals
/// never drift by a paisa.

/// No payment for this many days while money is pending = overdue.
const overdueDays = 30;

enum EntryKind {
  credit('CREDIT', 'Udhaar given'),
  payment('PAYMENT', 'Payment received');

  const EntryKind(this.code, this.label);

  final String code;
  final String label;

  static EntryKind? fromCode(Object? code) {
    for (final k in values) {
      if (k.code == code) return k;
    }
    return null;
  }
}

/// "This is not my number": the customer reports, only the shop decides.
enum Dispute {
  none('NONE'),

  /// The customer reported it; waiting for the shop.
  reported('REPORTED'),

  /// The shop says the number is right; cannot be reported again.
  confirmed('CONFIRMED'),

  /// The shop agrees it is the wrong number; hidden from that phone.
  unlinked('UNLINKED');

  const Dispute(this.code);

  final String code;

  static Dispute fromCode(Object? code) {
    for (final d in values) {
      if (d.code == code) return d;
    }
    return none;
  }
}

/// One customer in the shop's udhaar book.
class UdhaarCustomer {
  const UdhaarCustomer({
    required this.id,
    required this.name,
    required this.mobile,
    this.creditLimitPaise,
    this.balancePaise = 0,
    this.lastEntryAt,
    this.owingSince,
    this.dispute = Dispute.none,
    this.disputedAt,
  });

  final int id;
  final String name;
  final String mobile;
  final int? creditLimitPaise;

  /// Positive = the customer owes the shop. Negative = paid in advance.
  final int balancePaise;
  final DateTime? lastEntryAt;

  /// Since when money has been pending (last payment, or first udhaar).
  final DateTime? owingSince;

  /// "This is not my number" status, and when the customer reported it.
  final Dispute dispute;
  final DateTime? disputedAt;

  bool get overLimit =>
      creditLimitPaise != null && balancePaise > creditLimitPaise!;

  /// Days without a payment while money is pending (0 if nothing pending).
  int daysOwing(DateTime now) {
    final since = owingSince;
    if (since == null || balancePaise <= 0) return 0;
    return now.difference(since).inDays;
  }

  bool isOverdue(DateTime now) => daysOwing(now) >= overdueDays;

  UdhaarCustomer copyWith({
    String? name,
    int? balancePaise,
    DateTime? lastEntryAt,
    int? Function()? creditLimitPaise,
  }) => UdhaarCustomer(
    id: id,
    name: name ?? this.name,
    mobile: mobile,
    creditLimitPaise: creditLimitPaise != null
        ? creditLimitPaise()
        : this.creditLimitPaise,
    balancePaise: balancePaise ?? this.balancePaise,
    lastEntryAt: lastEntryAt ?? this.lastEntryAt,
    owingSince: owingSince,
    dispute: dispute,
    disputedAt: disputedAt,
  );

  static UdhaarCustomer? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final name = json['name'];
    final mobile = json['mobile'];
    if (id is! int || name is! String || mobile is! String) return null;
    return UdhaarCustomer(
      id: id,
      name: name,
      mobile: mobile,
      creditLimitPaise: _int(json['creditLimitPaise']),
      balancePaise: _int(json['balancePaise']) ?? 0,
      lastEntryAt: _time(json['lastEntryAt']),
      owingSince: _time(json['owingSince']),
      dispute: Dispute.fromCode(json['dispute']),
      disputedAt: _time(json['disputedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mobile': mobile,
    'creditLimitPaise': creditLimitPaise,
    'balancePaise': balancePaise,
    'lastEntryAt': lastEntryAt?.toUtc().toIso8601String(),
    'owingSince': owingSince?.toUtc().toIso8601String(),
    'dispute': dispute.code,
    'disputedAt': disputedAt?.toUtc().toIso8601String(),
  };
}

/// The whole book: every customer, and the money pending with all of them.
class UdhaarBook {
  const UdhaarBook(this.customers);

  final List<UdhaarCustomer> customers;

  /// Money pending with all customers (advances are not subtracted).
  int get totalPendingPaise =>
      customers.fold<int>(0, (sum, c) => sum + max(c.balancePaise, 0));

  int get pendingCustomers => customers.where((c) => c.balancePaise > 0).length;

  static UdhaarBook? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final list = json['customers'];
    if (list is! List) return null;
    return UdhaarBook(
      list.map(UdhaarCustomer.fromJson).whereType<UdhaarCustomer>().toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'customers': [for (final c in customers) c.toJson()],
  };
}

/// What the shopkeeper fills in for a new entry. [clientRef] is made on the
/// phone, so sending the same entry twice (after being offline) keeps one.
class EntryDraft {
  EntryDraft({
    required this.kind,
    required this.amountPaise,
    required this.entryAt,
    this.note = '',
    String? clientRef,
  }) : clientRef = clientRef ?? newClientRef();

  final EntryKind kind;
  final int amountPaise;
  final DateTime entryAt;
  final String note;
  final String clientRef;

  Map<String, dynamic> toJson() => {
    'kind': kind.code,
    'amountPaise': amountPaise,
    'note': note.trim().isEmpty ? null : note.trim(),
    'entryAt': entryAt.toUtc().toIso8601String(),
    'clientRef': clientRef,
  };

  static EntryDraft? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final kind = EntryKind.fromCode(json['kind']);
    final amount = _int(json['amountPaise']);
    final at = _time(json['entryAt']);
    final ref = json['clientRef'];
    if (kind == null || amount == null || at == null || ref is! String) {
      return null;
    }
    return EntryDraft(
      kind: kind,
      amountPaise: amount,
      entryAt: at,
      note: json['note'] as String? ?? '',
      clientRef: ref,
    );
  }
}

/// One line in a customer's history.
class UdhaarEntry {
  const UdhaarEntry({
    required this.id,
    required this.kind,
    required this.amountPaise,
    required this.entryAt,
    required this.clientRef,
    this.note,
    this.deletedAt,
    this.deleteReason,
    this.pending = false,
  });

  /// Entries saved on the phone and not yet on the server ([pending]) have no id.
  factory UdhaarEntry.pending(EntryDraft d) => UdhaarEntry(
    id: null,
    kind: d.kind,
    amountPaise: d.amountPaise,
    entryAt: d.entryAt,
    clientRef: d.clientRef,
    note: d.note.trim().isEmpty ? null : d.note.trim(),
    pending: true,
  );

  final int? id;
  final EntryKind kind;
  final int amountPaise;
  final DateTime entryAt;
  final String clientRef;
  final String? note;
  final DateTime? deletedAt;
  final String? deleteReason;
  final bool pending;

  bool get deleted => deletedAt != null;

  /// How this entry changes what the customer owes.
  int get effect => deleted
      ? 0
      : kind == EntryKind.credit
      ? amountPaise
      : -amountPaise;

  static UdhaarEntry? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final kind = EntryKind.fromCode(json['kind']);
    final amount = _int(json['amountPaise']);
    final at = _time(json['entryAt']);
    if (kind == null || amount == null || at == null) return null;
    return UdhaarEntry(
      id: _int(json['id']),
      kind: kind,
      amountPaise: amount,
      entryAt: at,
      clientRef: json['clientRef'] as String? ?? '',
      note: json['note'] as String?,
      deletedAt: _time(json['deletedAt']),
      deleteReason: json['deleteReason'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.code,
    'amountPaise': amountPaise,
    'entryAt': entryAt.toUtc().toIso8601String(),
    'clientRef': clientRef,
    'note': note,
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
    'deleteReason': deleteReason,
  };
}

/// One customer with their full history (newest first).
class CustomerDetail {
  const CustomerDetail({required this.customer, required this.entries});

  final UdhaarCustomer customer;
  final List<UdhaarEntry> entries;

  static CustomerDetail? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final customer = UdhaarCustomer.fromJson(json['customer']);
    final entries = json['entries'];
    if (customer == null || entries is! List) return null;
    return CustomerDetail(
      customer: customer,
      entries: entries.map(UdhaarEntry.fromJson).whereType<UdhaarEntry>().toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'customer': customer.toJson(),
    'entries': [for (final e in entries) e.toJson()],
  };
}

/// The customer's balance just after each entry. Deleted entries do not change it.
Map<UdhaarEntry, int> runningBalances(List<UdhaarEntry> newestFirst) {
  final result = <UdhaarEntry, int>{};
  var balance = 0;
  for (final e in newestFirst.reversed) {
    balance += e.effect;
    result[e] = balance;
  }
  return result;
}

/// One shop's book, as the customer sees it ("My Udhaar").
class MyBook {
  const MyBook({
    required this.bookId,
    required this.shopName,
    this.shopPhone,
    this.shopCategory,
    this.shopAddress,
    this.shopPhoto,
    this.balancePaise = 0,
    this.lastEntryAt,
    this.dispute = Dispute.none,
    this.verifiedAt,
    this.closed = false,
  });

  final int bookId;
  final String shopName;

  /// The shop left QBOX: only to look at.
  final bool closed;
  final String? shopPhone;
  final String? shopCategory;
  final String? shopAddress;

  /// The ref of the shop's photo.
  final String? shopPhoto;
  final int balancePaise;
  final DateTime? lastEntryAt;
  final Dispute dispute;

  /// When this number was checked with a code at the shop.
  final DateTime? verifiedAt;

  static MyBook? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['bookId'];
    final name = json['shopName'];
    if (id is! int || name is! String) return null;
    return MyBook(
      bookId: id,
      shopName: name,
      shopPhone: json['shopPhone'] as String?,
      shopCategory: json['shopCategory'] as String?,
      shopAddress: json['shopAddress'] as String?,
      shopPhoto: json['shopPhoto'] as String?,
      balancePaise: _int(json['balancePaise']) ?? 0,
      lastEntryAt: _time(json['lastEntryAt']),
      dispute: Dispute.fromCode(json['dispute']),
      verifiedAt: _time(json['verifiedAt']),
      closed: json['closed'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'bookId': bookId,
    'closed': closed,
    'shopName': shopName,
    'shopPhone': shopPhone,
    'shopCategory': shopCategory,
    'shopAddress': shopAddress,
    'shopPhoto': shopPhoto,
    'balancePaise': balancePaise,
    'lastEntryAt': lastEntryAt?.toUtc().toIso8601String(),
    'dispute': dispute.code,
    'verifiedAt': verifiedAt?.toUtc().toIso8601String(),
  };
}

class MyBookDetail {
  const MyBookDetail({required this.book, required this.entries});

  final MyBook book;
  final List<UdhaarEntry> entries;

  static MyBookDetail? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final book = MyBook.fromJson(json['book']);
    final entries = json['entries'];
    if (book == null || entries is! List) return null;
    return MyBookDetail(
      book: book,
      entries: entries.map(UdhaarEntry.fromJson).whereType<UdhaarEntry>().toList(),
    );
  }
}

/// The add-customer code was sent.
class InviteSent {
  const InviteSent({required this.resendInSeconds, this.devOtp});

  final int resendInSeconds;

  /// Test mode only (no SMS provider yet): the code itself.
  final String? devOtp;
}

// ---------- helpers ----------

/// ₹1,250 or ₹1,250.50 (Indian commas). Always positive; callers add words
/// like "due" or "advance".
String rupees(int paise) {
  final abs = paise.abs();
  final whole = abs ~/ 100;
  final rest = abs % 100;
  final grouped = _indianCommas(whole.toString());
  return rest == 0
      ? '₹$grouped'
      : '₹$grouped.${rest.toString().padLeft(2, '0')}';
}

String _indianCommas(String digits) {
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var head = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (head.length > 2) {
    parts.insert(0, head.substring(head.length - 2));
    head = head.substring(0, head.length - 2);
  }
  if (head.isNotEmpty) parts.insert(0, head);
  return '${parts.join(',')},$last3';
}

/// "1,250" / "1250.5" / "₹ 99" -> paise. Null if not a positive amount
/// with at most 2 decimals.
int? parsePaise(String text) {
  final clean = text.replaceAll(RegExp(r'[₹,\s]'), '');
  final match = RegExp(r'^([0-9]{1,9})(?:\.([0-9]{0,2}))?$').firstMatch(clean);
  if (match == null) return null;
  final whole = int.parse(match[1]!);
  final decimals = (match[2] ?? '').padRight(2, '0');
  final paise = whole * 100 + int.parse(decimals);
  return paise > 0 ? paise : null;
}

/// Paise as text for an amount field: 125050 -> "1250.50", 25000 -> "250".
String paiseToText(int paise) => paise % 100 == 0
    ? '${paise ~/ 100}'
    : '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

/// A phone number from contacts ("+91 98765-43210", "098765 43210") as the
/// 10 digits QBOX uses, or null if it is not an Indian mobile number.
String? normalizeMobile(String raw) {
  var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 12 && digits.startsWith('91')) digits = digits.substring(2);
  if (digits.length == 11 && digits.startsWith('0')) digits = digits.substring(1);
  return RegExp(r'^[6-9][0-9]{9}$').hasMatch(digits) ? digits : null;
}

/// "Today, 10:30 AM", "Yesterday, 6:05 PM", "19 Nov, 10:30 AM", "3 Jan 2025".
String whenLabel(DateTime at, DateTime now) {
  final local = at.toLocal();
  final time = timeLabel(local.hour * 60 + local.minute);
  if (isSameDay(local, now)) return 'Today, $time';
  if (isSameDay(local, now.subtract(const Duration(days: 1)))) {
    return 'Yesterday, $time';
  }
  final month = monthNames[local.month - 1].substring(0, 3);
  if (local.year == now.year) return '${local.day} $month, $time';
  return '${local.day} $month ${local.year}';
}

/// A random id for a new entry (32 hex characters).
String newClientRef() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : null);

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
