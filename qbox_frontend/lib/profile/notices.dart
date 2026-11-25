import 'package:flutter/material.dart';

import '../customer/expenses_screen.dart';
import '../customer/transactions_screen.dart';
import '../models/qbox_user.dart';
import '../onboarding_draft.dart';
import '../payments/payments_screen.dart';
import '../services/api_client.dart';
import '../stock/stock_screen.dart';
import '../suppliers/suppliers_screen.dart';
import '../supply/products_screen.dart';
import '../supply/supply_orders_screen.dart';
import '../supply/supply_payments_screen.dart';
import '../supply/supply_shops_screen.dart';
import '../udhaar/my_udhaar_screen.dart';
import '../udhaar/udhaar_models.dart' show rupees;
import '../udhaar/udhaar_screen.dart';
import '../udhaar/udhaar_widgets.dart';

/// The bell: what it can show, in words, and the screen each one opens.

/// What can be switched off, and for which role.
enum NoticeType {
  udhaar('UDHAAR', 'Udhaar', 'What shops write in your udhaar'),
  payment('PAYMENT', 'Payments', 'Payments to your shop, and UPI answers'),
  budget('BUDGET', 'Budget', 'When your monthly budget is nearly used'),
  customer('CUSTOMER', 'Customers', '"This is not my number" reports'),
  stock('STOCK', 'Low stock', 'Items running low'),
  supplier('SUPPLIER', 'Suppliers', 'Dues, and answers from connected suppliers'),
  order('ORDER', 'Orders', 'New, cancelled and received orders'),
  ledger('LEDGER', 'Shop ledger', 'Shops asking to connect, and entries to confirm');

  const NoticeType(this.code, this.label, this.about);

  final String code;
  final String label;
  final String about;

  static NoticeType? fromCode(Object? code) => values.where((t) => t.code == code).firstOrNull;

  static List<NoticeType> of(QboxRole role) => switch (role) {
    QboxRole.customer => const [udhaar, payment, budget],
    QboxRole.business => const [payment, customer, stock, supplier],
    QboxRole.supplier => const [order, ledger, stock],
  };
}

class Notice {
  const Notice({
    required this.id,
    required this.kind,
    required this.name,
    required this.at,
    this.amountPaise,
    this.note,
    this.testMode = false,
    this.unread = false,
  });

  final String id;

  /// The server's word for what happened ("CREDIT"). One this app does not know is not shown.
  final String kind;

  /// The shop, customer, item or supplier.
  final String name;
  final int? amountPaise;
  final String? note;
  final bool testMode;
  final DateTime at;
  final bool unread;

  Notice read() =>
      Notice(id: id, kind: kind, name: name, at: at, amountPaise: amountPaise, note: note, testMode: testMode);

  static Notice? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final kind = json['kind'];
    final name = json['name'];
    final at = DateTime.tryParse('${json['at']}');
    if (id is! String || kind is! String || name is! String || at == null || !_words.containsKey(kind)) return null;
    return Notice(
      id: id,
      kind: kind,
      name: name,
      amountPaise: json['amountPaise'] is int ? json['amountPaise'] as int : null,
      note: json['note'] is String ? json['note'] as String : null,
      testMode: json['testMode'] == true,
      at: at.toLocal(),
      unread: json['unread'] == true,
    );
  }

  _Words get _w => _words[kind]!;

  IconData get icon => _w.icon;
  Color get color => _w.color;
  String get title => _w.title(this);
  Widget get screen => _w.screen();

  /// The second line; null = none.
  String? get detail => _w.detail?.call(this) ?? note;

  String get amount => rupees(amountPaise ?? 0);

  /// "2 kg left" from "2000 KG".
  String get left {
    final parts = (note ?? '').split(' ');
    final milli = int.tryParse(parts.first);
    if (milli == null || parts.length != 2) return '';
    final text = (milli / 1000).toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
    return '$text ${parts[1].toLowerCase()} left';
  }
}

class Notices {
  const Notices({this.unread = 0, this.off = const {}, this.items = const []});

  final int unread;
  final Set<NoticeType> off;
  final List<Notice> items;

  static Notices? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final items = json['notices'];
    if (items is! List) return null;
    return Notices(
      unread: json['unread'] is int ? json['unread'] as int : 0,
      off: {for (final t in json['off'] as List? ?? const []) ?NoticeType.fromCode(t)},
      items: items.map(Notice.fromJson).whereType<Notice>().toList(),
    );
  }
}

/// Needs login.
abstract class NoticesApi {
  Future<Notices> all(QboxRole role);

  Future<int> unread(QboxRole role);

  /// [id] null = all.
  Future<void> markRead(QboxRole role, {String? id});

  Future<void> setOff(QboxRole role, Set<NoticeType> off);
}

class HttpNoticesApi implements NoticesApi {
  HttpNoticesApi(this._api);

  final ApiClient _api;

  static const _base = '/api/notices';

  @override
  Future<Notices> all(QboxRole role) async {
    final notices = Notices.fromJson(await _api.get('$_base?role=${roleCode(role)}'));
    if (notices == null) throw const ApiException('ERROR', 'Something went wrong. Please try again.');
    return notices;
  }

  @override
  Future<int> unread(QboxRole role) async {
    final json = await _api.get('$_base/unread?role=${roleCode(role)}');
    return json is Map<String, dynamic> && json['unread'] is int ? json['unread'] as int : 0;
  }

  @override
  Future<void> markRead(QboxRole role, {String? id}) => _api.post('$_base/read', {'role': roleCode(role), 'id': id});

  @override
  Future<void> setOff(QboxRole role, Set<NoticeType> off) => _api.put('$_base/off', {
    'role': roleCode(role),
    'off': [for (final t in off) t.code],
  });
}

class _Words {
  const _Words(this.icon, this.color, this.title, this.screen, [this.detail]);

  final IconData icon;
  final Color color;
  final String Function(Notice n) title;
  final Widget Function() screen;
  final String? Function(Notice n)? detail;
}

Widget _myUdhaar() => const MyUdhaarScreen();
Widget _history() => const TransactionsScreen();
Widget _expenses() => const ExpensesScreen();
Widget _payments() => const PaymentsScreen();
Widget _book() => const UdhaarScreen();
Widget _stock() => const StockScreen();
Widget _suppliers() => const SuppliersScreen();
Widget _orders() => const SupplyOrdersScreen();
Widget _ledger() => const SupplyShopsScreen();
Widget _products() => const ProductsScreen();
Widget _received() => const SupplyPaymentsScreen();

final _words = <String, _Words>{
  'ADDED': _Words(Icons.menu_book_rounded, udPurple, (n) => '${n.name} added you to its udhaar book', _myUdhaar),
  'CREDIT': _Words(Icons.south_west_rounded, udDue, (n) => '${n.name} wrote ${n.amount} udhaar', _myUdhaar),
  'RECORDED': _Words(
    Icons.north_east_rounded,
    udPaid,
    (n) => '${n.name} recorded your payment of ${n.amount}',
    _myUdhaar,
  ),
  'DELETED': _Words(
    Icons.delete_outline_rounded,
    udWarn,
    (n) => '${n.name} deleted ${n.amount} from your udhaar',
    _myUdhaar,
  ),
  'NUMBER_KEPT': _Words(
    Icons.person_outline,
    udWarn,
    (n) => '${n.name} says this number is yours',
    _myUdhaar,
    (_) => 'Talk to the shop if it is not.',
  ),
  'NUMBER_REMOVED': _Words(
    Icons.person_off_outlined,
    udPaid,
    (n) => '${n.name} removed your number from its book',
    _myUdhaar,
  ),
  'RECEIVED': _Words(
    Icons.check_circle_outline_rounded,
    udPaid,
    (n) => '${n.name} received your ${n.amount}',
    _history,
  ),
  'NOT_RECEIVED': _Words(
    Icons.error_outline_rounded,
    udDue,
    (n) => '${n.name} did not receive ${n.amount}',
    _history,
    (_) => 'Check your UPI app, or talk to the shop.',
  ),
  'BUDGET_NEAR': _Words(
    Icons.savings_outlined,
    udWarn,
    (_) => 'Most of this month\'s budget is used',
    _expenses,
    (n) => '${n.amount} spent so far',
  ),
  'BUDGET_OVER': _Words(
    Icons.savings_outlined,
    udDue,
    (_) => 'You are over this month\'s budget',
    _expenses,
    (n) => 'It was crossed at ${n.amount}',
  ),
  'PAID_ONLINE': _Words(Icons.south_west_rounded, udPaid, (n) => '${n.name} paid ${n.amount} online', _payments),
  'SAYS_PAID': _Words(
    Icons.help_outline_rounded,
    udWarn,
    (n) => '${n.name} says they paid ${n.amount} by UPI',
    _payments,
    (_) => 'Check your bank, then confirm.',
  ),
  'NOT_ME': _Words(
    Icons.report_gmailerrorred_rounded,
    udWarn,
    (n) => '${n.name}: "This is not my number"',
    _book,
    (_) => 'Please check and decide.',
  ),
  'LOW_STOCK': _Words(Icons.inventory_2_outlined, udWarn, (n) => '${n.name} is running low', _stock, (n) => n.left),
  'CONNECTED': _Words(Icons.link_rounded, udPaid, (n) => '${n.name} connected with you', _suppliers),
  'NOT_CONNECTED': _Words(Icons.link_off_rounded, udWarn, (n) => '${n.name} did not connect', _suppliers),
  'SUPPLIER_LEFT': _Words(Icons.link_off_rounded, udWarn, (n) => '${n.name} disconnected', _suppliers),
  'ORDER_ACCEPTED': _Words(
    Icons.check_circle_outline_rounded,
    udPaid,
    (n) => '${n.name} accepted your order: bill ${n.amount}',
    _suppliers,
  ),
  'ORDER_REJECTED': _Words(Icons.cancel_outlined, udDue, (n) => '${n.name} rejected your order', _suppliers),
  'ORDER_SENT': _Words(Icons.local_shipping_outlined, udPurple, (n) => '${n.name}: your goods are on the way', _suppliers),
  'MONEY_CONFIRMED': _Words(Icons.check_circle_outline_rounded, udPaid, (n) => '${n.name} received your ${n.amount}', _suppliers),
  'NOT_RIGHT': _Words(Icons.error_outline_rounded, udDue, (n) => '${n.name} says ${n.amount} is not right', _suppliers),
  'WANTS_TO_CONNECT': _Words(
    Icons.link_rounded,
    udPurple,
    (n) => '${n.name} wants to connect',
    _ledger,
    (_) => 'Check the amount and answer.',
  ),
  'THEY_GAVE': _Words(
    Icons.help_outline_rounded,
    udWarn,
    (n) => '${n.name} wrote goods of ${n.amount}. Is it right?',
    _suppliers,
  ),
  'THEY_GOT': _Words(
    Icons.payments_outlined,
    udPaid,
    (n) => '${n.name} wrote that you paid ${n.amount}',
    _suppliers,
  ),
  'THEY_DELETED': _Words(
    Icons.delete_outline_rounded,
    udWarn,
    (n) => '${n.name} deleted an entry of ${n.amount}',
    _suppliers,
  ),
  'SHOP_AGREED': _Words(
    Icons.check_circle_outline_rounded,
    udPaid,
    (n) => '${n.name} confirmed ${n.amount}',
    _ledger,
  ),
  'SHOP_NOT_RIGHT': _Words(
    Icons.error_outline_rounded,
    udDue,
    (n) => '${n.name} says ${n.amount} is not right',
    _ledger,
  ),
  'PRODUCT_LOW': _Words(
    Icons.inventory_2_outlined,
    udWarn,
    (n) => '${n.name} is running low',
    _products,
    (n) => n.left,
  ),
  'SHOP_LEFT': _Words(Icons.link_off_rounded, udWarn, (n) => '${n.name} disconnected', _ledger),
  'NEW_ORDER': _Words(Icons.add_shopping_cart_rounded, udWarn, (n) => 'New order from ${n.name}', _orders),
  'ORDER_CANCELLED': _Words(Icons.cancel_outlined, udDue, (n) => '${n.name} cancelled an order', _orders),
  'ORDER_RECEIVED': _Words(Icons.inventory_2_outlined, udPaid, (n) => '${n.name} received the goods', _orders),
  'CONFIRM_PURCHASE': _Words(
    Icons.help_outline_rounded,
    udWarn,
    (n) => '${n.name} wrote goods for ${n.amount}',
    _ledger,
    (n) => n.note ?? 'Please check it.',
  ),
  'CONFIRM_PAYMENT': _Words(
    Icons.help_outline_rounded,
    udWarn,
    (n) => '${n.name} says they paid ${n.amount}',
    _received,
    (_) => 'Confirm when the money came.',
  ),
  'ENTRY_DELETED': _Words(Icons.delete_outline_rounded, udWarn, (n) => '${n.name} deleted ${n.amount}', _ledger),
  'SUPPLIER_DUE': _Words(
    Icons.local_shipping_outlined,
    udDue,
    (n) => 'Pay ${n.name}',
    _suppliers,
    (n) => '${n.amount} is due',
  ),
};
