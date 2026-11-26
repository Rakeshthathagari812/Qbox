import 'package:flutter/material.dart';

import '../calendar/calendar_models.dart';
import '../calendar/calendar_screen.dart';
import '../calendar/event_form_screen.dart';
import '../calendar/spoken_time.dart';
import '../calendar/voice_event.dart';
import '../customer/checklist_notes_screen.dart';
import '../customer/expenses_screen.dart';
import '../customer/pay_shop_screen.dart';
import '../customer/transaction_models.dart';
import '../customer/transactions_screen.dart';
import '../onboarding_draft.dart';
import '../payments/payments_screen.dart';
import '../services/api_client.dart';
import '../services/app_services.dart';
import '../stock/item_screen.dart';
import '../stock/stock_models.dart';
import '../stock/stock_screen.dart';
import '../stock/stock_widgets.dart';
import '../stock/heard_items.dart';
import '../stock/voice_stock.dart';
import '../suppliers/supplier_models.dart';
import '../suppliers/supplier_screen.dart';
import '../suppliers/suppliers_screen.dart';
import '../supply/product_stock_screen.dart';
import '../supply/products_screen.dart';
import '../supply/supply_models.dart';
import '../supply/supply_orders_screen.dart';
import '../supply/supply_payments_screen.dart';
import '../supply/supply_report_screen.dart';
import '../supply/supply_shop_screen.dart';
import '../supply/supply_shops_screen.dart';
import '../translator/indic_numbers.dart';
import '../translator/languages.dart';
import '../translator/transliterate.dart';
import '../udhaar/customer_screen.dart';
import '../udhaar/entry_form_screen.dart';
import '../udhaar/my_udhaar_screen.dart';
import '../udhaar/udhaar_models.dart';
import '../udhaar/udhaar_screen.dart';
import '../udhaar/voice_udhaar.dart';
import 'ask_words.dart';

/// One line under an answer.
class AskRow {
  const AskRow(this.title, {this.detail = '', this.amount = '', this.open});

  final String title;
  final String detail;
  final String amount;

  /// The screen it opens.
  final WidgetBuilder? open;
}

/// A button under an answer. It opens a screen; nothing is ever saved from here.
class AskAction {
  const AskAction(this.label, this.run);

  final String label;
  final Future<void> Function(BuildContext context) run;
}

class AskAnswer {
  const AskAnswer(this.text, {this.rows = const [], this.action, this.understood = true, this.saved = false});

  final String text;
  final List<AskRow> rows;
  final AskAction? action;
  final bool understood;

  /// Worked out from the copy on the phone (no internet).
  final bool saved;
}

const _rowsShown = 8;

/// Understands a question and answers it from the user's own records. The same
/// rules for every language: the words are matched in their own language first,
/// and only if that fails, in English.
class AskBrain {
  AskBrain(this.app, this.role, {DateTime? now}) : now = now ?? DateTime.now();

  final AppServices app;
  final QboxRole role;
  final DateTime now;

  AppLanguage _lang = AppLanguage.english;
  bool _saved = false;

  /// [english] translates [words]; asked only when needed. Throws [ApiException].
  Future<AskAnswer> ask(String words, AppLanguage language, {Future<String?> Function()? english}) async {
    _lang = language;
    _saved = false;
    final text = fixHeard(numbersToDigits(words, language));
    // Names saved in English, said in another script.
    final heard = '${text.toLowerCase()} ${transliterate(text).toLowerCase()}';
    try {
      final first = await _answer(text, heard, english);
      if (first != null) return first;
      if (language != AppLanguage.english && english != null) {
        final translated = await english();
        if (translated != null && translated.trim().isNotEmpty) {
          final second = await _answer(translated, '$heard ${translated.toLowerCase()}', () async => translated);
          if (second != null) return second;
        }
      }
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      return AskAnswer(_say('needNet'), understood: true);
    }
    return AskAnswer(_say('sorry'), understood: false);
  }

  String _say(String key, {String a = '', String b = '', String c = ''}) => askSays(key, _lang, a: a, b: b, c: c);

  Future<AskAnswer?> _answer(String text, String heard, Future<String?> Function()? english) async {
    final about = conceptsIn(text);
    if (about.contains(Concept.help)) return AskAnswer(_say('help'), understood: false);
    if (about.contains(Concept.remindMe)) {
      final event = await _reminder(text, english);
      if (event != null) return event;
    }
    return switch (role) {
      QboxRole.business => _shop(text, heard, about, english),
      QboxRole.customer => _customer(heard, about),
      QboxRole.supplier => _supplier(heard, about),
    };
  }

  // ---------- data: the server's, or the copy on the phone ----------

  Future<T> _get<T>(Future<T> Function() fresh, Future<T?> Function() saved) async {
    try {
      return await fresh();
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      final copy = await saved();
      if (copy == null) rethrow;
      _saved = true;
      return copy;
    }
  }

  Future<UdhaarBook> _book() => _get(app.udhaar.freshBook, app.udhaar.savedBook);
  Future<StockBook> _stock() => _get(app.stock.freshBook, app.stock.savedBook);
  Future<SupplierBook> _suppliers() => _get(app.suppliers.freshBook, app.suppliers.savedBook);
  Future<List<MyBook>> _myBooks() => _get(app.udhaar.freshMyBooks, app.udhaar.savedMyBooks);
  Future<MonthHistory> _month() {
    final key = monthKey(now);
    return _get(() => app.transactions.fresh(key), () => app.transactions.saved(key));
  }

  Future<SupplyHome> _supplyHome() => _get(app.supply.home, app.supply.savedHome);
  Future<List<SupplyOrder>> _orders() => _get(app.supply.orders, app.supply.savedOrders);
  Future<List<Product>> _products() => _get(app.supply.products, app.supply.savedProducts);

  AskAnswer _reply(String text, {List<AskRow> rows = const [], WidgetBuilder? open, AskAction? action}) => AskAnswer(
    text,
    rows: rows,
    saved: _saved,
    action: action ?? (open == null ? null : AskAction(_say('open'), (context) => _push(context, open))),
  );

  static Future<void> _push(BuildContext context, WidgetBuilder open) =>
      Navigator.of(context).push<void>(MaterialPageRoute(builder: open));

  // ---------- shop ----------

  Future<AskAnswer?> _shop(String text, String heard, Set<Concept> about, Future<String?> Function()? english) async {
    final supplierTalk = about.contains(Concept.supplier);
    if (about.contains(Concept.calendar)) return _calendar(about);

    // "Ramesh 250 udhaar", "rice 10 kg came": the form, filled in.
    if (!supplierTalk) {
      final book = await _book();
      final customers = _named(heard, book.customers, (c) => c.name);
      final stock = await _stock();
      final move = parseSpokenStock(text, _lang, stock.items);
      if (move != null && move.matches.isNotEmpty && move.qtyMilli != null && move.kind != null && customers.isEmpty) {
        return _stockMove(move, text);
      }
      if (customers.isNotEmpty) {
        // Who gave and who took is only sure in English: another language is translated.
        final said = _lang == AppLanguage.english || digitsAmount(text) == null ? text : await english?.call();
        final spoken = said == null ? null : parseSpokenUdhaar(said, customers);
        final amount = digitsAmount(text) ?? spoken?.amountPaise;
        // Which way: read from the Telugu/Hindi words first (translation mixes it up).
        if (amount != null) return _entry(nativeKind(text, _lang) ?? spoken?.kind, customers, amount, text);
        return _customersOwe(customers);
      }

      final suppliers = await _suppliers();
      final named = _named(heard, suppliers.suppliers, (s) => s.name);
      if (named.isNotEmpty) return _supplierBalance(named);
      if (move != null && move.matches.isNotEmpty) return _items(move.matches);
    } else {
      final suppliers = await _suppliers();
      final named = _named(heard, suppliers.suppliers, (s) => s.name);
      if (named.isNotEmpty) return _supplierBalance(named);
    }

    if (about.contains(Concept.order)) return _shopOrders();
    if (supplierTalk) return _oweSuppliers();
    if (about.contains(Concept.value)) return _stockValue();
    if (about.contains(Concept.low)) return _lowStock();
    if (about.contains(Concept.late)) return _late();
    if (_owing(about) && about.contains(Concept.most)) return _owedMost();
    if (_money(about) && about.contains(Concept.confirm)) return _paymentsToConfirm();
    if (_owing(about)) return _owedTotal();
    if (_money(about)) return _paidToday();
    if (about.contains(Concept.stock)) return _stockAll();
    return null;
  }

  /// [kind] null = it is not sure which way: both are offered.
  AskAnswer _entry(EntryKind? kind, List<UdhaarCustomer> found, int amount, String heard) {
    WidgetBuilder form(UdhaarCustomer c, EntryKind k) =>
        (_) => UdhaarEntryForm(customer: c, kind: k, amountPaise: amount, fromVoice: true, heard: heard);
    final kinds = kind == null ? EntryKind.values : [kind];
    if (found.length == 1 && kind != null) {
      final c = found.single;
      return _reply(
        _say(kind == EntryKind.credit ? 'writeUdhaar' : 'writePayment', a: c.name, b: rupees(amount)),
        action: AskAction(_say('check'), (context) => _push(context, form(c, kind))),
      );
    }
    return _reply(
      found.length > 1 ? _say('which') : _say('whichWay', a: found.single.name, b: rupees(amount)),
      rows: [
        for (final c in found)
          for (final k in kinds)
            AskRow(
              found.length > 1 ? c.name : _say(k == EntryKind.credit ? 'udhaar' : 'payment'),
              detail: found.length > 1 ? c.mobile : '',
              amount: rupees(amount),
              open: form(c, k),
            ),
      ],
    );
  }

  AskAnswer _stockMove(SpokenStock move, String heard) {
    Future<void> sheet(BuildContext context, StockItem item) async {
      await showMoveSheet(
        context,
        item: item,
        kind: move.kind!,
        qtyMilli: move.qtyFor(item),
        heard: heard,
        save: (draft) => app.stock.addMove(item.id, draft),
      );
    }

    if (move.matches.length > 1) return _items(move.matches);
    final item = move.matches.single;
    return _reply(
      _say(
        move.kind == MoveKind.out ? 'stockOut' : 'stockIn',
        a: item.name,
        b: formatQty(move.qtyFor(item) ?? 0, item.unit),
      ),
      action: AskAction(_say('check'), (context) => sheet(context, item)),
    );
  }

  AskAnswer _customersOwe(List<UdhaarCustomer> found) {
    final c = found.first;
    return _reply(
      found.length > 1
          ? _say('which')
          : c.balancePaise > 0
          ? _say('owesYou', a: c.name, b: rupees(c.balancePaise))
          : c.balancePaise < 0
          ? _say('advance', a: c.name, b: rupees(c.balancePaise.abs()))
          : _say('owesNothing', a: c.name),
      rows: [if (found.length > 1) ...found.map(_customerRow)],
      open: found.length > 1 ? null : (_) => UdhaarCustomerScreen(customer: c),
    );
  }

  AskRow _customerRow(UdhaarCustomer c) => AskRow(
    c.name,
    detail: c.mobile,
    amount: balanceText(c.balancePaise),
    open: (_) => UdhaarCustomerScreen(customer: c),
  );

  Future<List<UdhaarCustomer>> _whoOwe() async =>
      (await _book()).customers.where((c) => c.balancePaise > 0).toList()
        ..sort((a, b) => b.balancePaise.compareTo(a.balancePaise));

  Future<AskAnswer> _owedMost() async {
    final owing = await _whoOwe();
    if (owing.isEmpty) return _reply(_say('owedNone'));
    return _reply(
      _say('owedMost', a: owing.first.name, b: rupees(owing.first.balancePaise)),
      rows: owing.take(_rowsShown).map(_customerRow).toList(),
      open: openUdhaar,
    );
  }

  Future<AskAnswer> _owedTotal() async {
    final owing = await _whoOwe();
    if (owing.isEmpty) return _reply(_say('owedNone'));
    final total = owing.fold(0, (s, c) => s + c.balancePaise);
    return _reply(
      _say('owedTotal', a: '${owing.length}', b: rupees(total)),
      rows: owing.take(_rowsShown).map(_customerRow).toList(),
      open: openUdhaar,
    );
  }

  Future<AskAnswer> _late() async {
    final late = (await _whoOwe()).where((c) => c.isOverdue(now)).toList();
    if (late.isEmpty) return _reply(_say('lateNone'));
    return _reply(_say('late', a: '${late.length}'), rows: late.take(_rowsShown).map(_customerRow).toList(), open: openUdhaar);
  }

  AskRow _itemRow(StockItem i) =>
      AskRow(i.name, amount: formatQty(i.quantityMilli, i.unit), open: (_) => ItemScreen(item: i, language: _lang));

  AskAnswer _items(List<StockItem> items) => _reply(
    items.length == 1
        ? _say('have', a: items.single.name, b: formatQty(items.single.quantityMilli, items.single.unit))
        : _say('which'),
    rows: [if (items.length > 1) ...items.take(_rowsShown).map(_itemRow)],
    open: items.length > 1 ? null : (_) => ItemScreen(item: items.single, language: _lang),
  );

  Future<AskAnswer> _lowStock() async {
    final low = (await _stock()).items.where((i) => i.isLow).toList();
    if (low.isEmpty) return _reply(_say('lowNone'), open: openStock);
    return _reply(_say('low', a: '${low.length}'), rows: low.take(_rowsShown).map(_itemRow).toList(), open: openStock);
  }

  Future<AskAnswer> _stockAll() async {
    final items = (await _stock()).items;
    final low = items.where((i) => i.isLow).length;
    return _reply(_say('stockAll', a: '${items.length}', b: '$low'), open: openStock);
  }

  Future<AskAnswer> _stockValue() async {
    final total = (await _stock()).items.fold(0, (s, i) => s + (i.valuePaise ?? 0));
    return _reply(_say('stockValue', a: rupees(total)), open: openStock);
  }

  Future<AskAnswer> _paidToday() async {
    final day = await app.payments.today();
    return _reply(
      _say('paidToday', a: rupees(day.totalPaise)),
      rows: [
        for (final p in day.payments.take(_rowsShown))
          AskRow(p.customerName ?? p.payerVpa ?? p.note ?? 'Payment', amount: rupees(p.amountPaise)),
      ],
      open: openPayments,
    );
  }

  Future<AskAnswer> _paymentsToConfirm() async {
    final waiting = (await app.payments.today()).toConfirm;
    return _reply(
      waiting.isEmpty ? _say('confirmNone') : _say('toConfirm', a: '${waiting.length}'),
      rows: [
        for (final p in waiting.take(_rowsShown))
          AskRow(p.customerName ?? p.note ?? 'Payment', amount: rupees(p.amountPaise)),
      ],
      open: openPayments,
    );
  }

  AskRow _supplierRow(Supplier s) => AskRow(
    s.name,
    amount: balanceText(s.balancePaise),
    open: (_) => SupplierScreen(supplier: s),
  );

  Future<AskAnswer> _oweSuppliers() async {
    final owed = (await _suppliers()).suppliers.where((s) => s.balancePaise > 0).toList()
      ..sort((a, b) => b.balancePaise.compareTo(a.balancePaise));
    final total = owed.fold(0, (s, x) => s + x.balancePaise);
    return _reply(
      _say('oweSuppliers', a: rupees(total)),
      rows: owed.take(_rowsShown).map(_supplierRow).toList(),
      open: openSuppliers,
    );
  }

  AskAnswer _supplierBalance(List<Supplier> found) {
    if (found.length > 1) return _reply(_say('which'), rows: found.take(_rowsShown).map(_supplierRow).toList());
    final s = found.single;
    return _reply(_youOwe(s.name, s.balancePaise), open: (_) => SupplierScreen(supplier: s));
  }

  /// About what is still owed ("not paid" too); "paid" alone is about money that moved.
  static bool _owing(Set<Concept> about) => about.contains(Concept.owe);

  static bool _money(Set<Concept> about) => about.contains(Concept.money) || about.contains(Concept.came);

  String _youOwe(String name, int paise) => paise > 0
      ? _say('youOwe', a: name, b: rupees(paise))
      : paise < 0
      ? _say('youPaidAdvance', a: name, b: rupees(paise.abs()))
      : _say('youOweNothingTo', a: name);

  Future<AskAnswer> _shopOrders() async {
    final waiting = (await _suppliers()).suppliers.where((s) => s.openOrders > 0).toList();
    final count = waiting.fold(0, (n, s) => n + s.openOrders);
    if (count == 0) return _reply(_say('ordersNone'), open: openSuppliers);
    return _reply(
      _say('orders', a: '$count'),
      rows: [
        for (final s in waiting.take(_rowsShown))
          AskRow(s.name, amount: '${s.openOrders}', open: (_) => SupplierScreen(supplier: s)),
      ],
      open: openSuppliers,
    );
  }

  // ---------- customer ----------

  Future<AskAnswer?> _customer(String heard, Set<Concept> about) async {
    if (about.contains(Concept.calendar)) return _calendar(about);
    if (about.contains(Concept.budget)) return _spent(budget: true);
    if (about.contains(Concept.spend)) return _spent();
    if (about.contains(Concept.list)) return _lists();

    final books = await _myBooks();
    final named = _named(heard, books, (b) => b.shopName);
    if (named.isNotEmpty && (!about.contains(Concept.pay) || _owing(about))) return _dueAt(named);
    if (_owing(about)) return _myDues(books);
    if (about.contains(Concept.came)) return _lastPaid();
    if (about.contains(Concept.pay)) return _reply(_say('payShop'), open: openPayShop);
    if (_money(about)) return _lastPaid();
    return null;
  }

  AskRow _bookRow(MyBook b) =>
      AskRow(b.shopName, amount: balanceText(b.balancePaise), open: (_) => MyBookScreen(book: b));

  AskAnswer _dueAt(List<MyBook> found) {
    if (found.length > 1) return _reply(_say('which'), rows: found.take(_rowsShown).map(_bookRow).toList());
    final b = found.single;
    return _reply(_youOwe(b.shopName, b.balancePaise), open: (_) => MyBookScreen(book: b));
  }

  AskAnswer _myDues(List<MyBook> books) {
    final owed = books.where((b) => b.balancePaise > 0).toList();
    if (owed.isEmpty) return _reply(_say('youOweNone'), open: openMyUdhaar);
    final total = owed.fold(0, (s, b) => s + b.balancePaise);
    return _reply(
      _say('youOweTotal', a: '${owed.length}', b: rupees(total)),
      rows: owed.take(_rowsShown).map(_bookRow).toList(),
      open: openMyUdhaar,
    );
  }

  Future<AskAnswer> _spent({bool budget = false}) async {
    final month = await _month();
    final spent = totalSpent(month.items);
    final limit = month.budgetPaise;
    final text = !budget || limit == null
        ? _say('spent', a: rupees(spent))
        : spent > limit
        ? _say('budgetOver', a: rupees(spent), b: rupees(limit), c: rupees(spent - limit))
        : _say('budgetLeft', a: rupees(spent), b: rupees(limit), c: rupees(limit - spent));
    return _reply(
      text,
      rows: [
        for (final (category, paise) in spentByCategory(month.items).take(_rowsShown))
          AskRow(category.label, amount: rupees(paise)),
      ],
      open: openExpenses,
    );
  }

  Future<AskAnswer> _lastPaid() async {
    final paid = (await _month()).items.where((t) => t.kind == EntryKind.payment && t.counts).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    if (paid.isEmpty) return _reply(_say('lastPaidNone'), open: openTransactions);
    return _reply(
      _say('lastPaid', a: '${paid.length}', b: rupees(totalPaid(paid))),
      rows: [
        for (final t in paid.take(_rowsShown))
          AskRow(t.shopName, detail: whenLabel(t.at, now), amount: rupees(t.amountPaise)),
      ],
      open: openTransactions,
    );
  }

  Future<AskAnswer> _lists() async {
    await app.pages.open();
    final lists = app.pages.pages.where((p) => p.isList && p.left.isNotEmpty).toList();
    if (lists.isEmpty) return _reply(_say('listsNone'), open: openChecklistNotes);
    final left = [for (final p in lists) ...p.left];
    return _reply(
      _say('lists', a: '${left.length}'),
      rows: [for (final i in left.take(_rowsShown)) AskRow(i.text, amount: i.qty)],
      open: openChecklistNotes,
    );
  }

  // ---------- supplier ----------

  Future<AskAnswer?> _supplier(String heard, Set<Concept> about) async {
    if (about.contains(Concept.calendar)) return _calendar(about);
    if (about.contains(Concept.order)) return _supplyOrders();
    if (about.contains(Concept.connect)) return _requests();
    if (about.contains(Concept.low)) return _lowProducts();

    final home = await _supplyHome();
    final shops = _named(heard, home.shops.where((s) => s.connected).toList(), (s) => s.name);
    if (shops.isNotEmpty) return _shopOwes(shops);
    final products = await _products();
    final named = _named(heard, products, (p) => p.name);
    if (named.isNotEmpty) return _productStock(named);

    if (_money(about) && about.contains(Concept.confirm)) return _supplyPayments(confirm: true);
    if (_owing(about)) return _toGet(home);
    if (_money(about)) return _supplyPayments();
    if (about.contains(Concept.given)) return _given();
    if (about.contains(Concept.stock)) return _lowProducts();
    return null;
  }

  Future<AskAnswer> _supplyOrders() async {
    final orders = (await _orders()).where((o) => o.connected).toList();
    final fresh = orders.where((o) => o.status == OrderStatus.sent).toList();
    final toSend = orders.where((o) => o.status == OrderStatus.accepted).toList();
    if (fresh.isEmpty && toSend.isEmpty) return _reply(_say('ordersNone'), open: openSupplyOrders);
    return _reply(
      _say('newOrders', a: '${fresh.length}', b: '${toSend.length}'),
      rows: [
        for (final o in [...fresh, ...toSend].take(_rowsShown))
          AskRow(
            o.shopName,
            detail: supplyLinesText(o.lines),
            amount: o.totalPaise == null ? '' : rupees(o.totalPaise!),
          ),
      ],
      open: openSupplyOrders,
    );
  }

  Future<AskAnswer> _requests() async {
    final asking = (await _supplyHome()).requests;
    return _reply(
      asking.isEmpty ? _say('requestsNone') : _say('requests', a: '${asking.length}'),
      rows: [for (final r in asking.take(_rowsShown)) AskRow(r.name, detail: r.phone ?? '')],
      open: openSupplyShops,
    );
  }

  AskRow _shopRow(SupplyShop s) =>
      AskRow(s.name, amount: balanceText(s.balancePaise), open: (_) => SupplyShopScreen(shop: s));

  AskAnswer _shopOwes(List<SupplyShop> found) {
    if (found.length > 1) return _reply(_say('which'), rows: found.take(_rowsShown).map(_shopRow).toList());
    final s = found.single;
    return _reply(
      s.balancePaise > 0
          ? _say('owesYou', a: s.name, b: rupees(s.balancePaise))
          : s.balancePaise < 0
          ? _say('advance', a: s.name, b: rupees(s.balancePaise.abs()))
          : _say('owesNothing', a: s.name),
      open: (_) => SupplyShopScreen(shop: s),
    );
  }

  AskAnswer _toGet(SupplyHome home) {
    final owing = home.shops.where((s) => s.connected && s.balancePaise > 0).toList()
      ..sort((a, b) => b.balancePaise.compareTo(a.balancePaise));
    return _reply(
      _say('toGet', a: rupees(home.totalDuePaise)),
      rows: owing.take(_rowsShown).map(_shopRow).toList(),
      open: openSupplyShops,
    );
  }

  Future<AskAnswer> _supplyPayments({bool confirm = false}) async {
    final p = await _get(app.supply.payments, app.supply.savedPayments);
    final waiting = p.payments
        .where((x) => x.connected && !x.entry.bySupplier && x.entry.confirm == Confirm.waiting)
        .toList();
    return _reply(
      confirm
          ? (waiting.isEmpty ? _say('confirmNone') : _say('toConfirm', a: '${waiting.length}'))
          : _say('received', a: rupees(p.receivedMonthPaise)),
      rows: [
        for (final x in waiting.take(_rowsShown)) AskRow(x.shopName, amount: rupees(x.entry.amountPaise)),
      ],
      open: openSupplyPayments,
    );
  }

  Future<AskAnswer> _given() async {
    final r = await app.supply.api.report(DateTime(now.year, now.month), DateTime(now.year, now.month, now.day));
    return _reply(
      _say('given', a: rupees(r.givenPaise)),
      rows: [for (final s in r.shops.take(_rowsShown)) AskRow(s.name, amount: rupees(s.givenPaise))],
      open: openSupplyReport,
    );
  }

  AskRow _productRow(Product p) => AskRow(
    p.name,
    amount: p.counted ? formatQty(p.quantityMilli, p.unit) : '',
    open: (_) => ProductStockScreen(product: p),
  );

  Future<AskAnswer> _lowProducts() async {
    final low = (await _products()).where((p) => p.low).toList();
    if (low.isEmpty) return _reply(_say('lowNone'), open: openProducts);
    return _reply(_say('low', a: '${low.length}'), rows: low.take(_rowsShown).map(_productRow).toList(), open: openProducts);
  }

  AskAnswer _productStock(List<Product> found) {
    if (found.length > 1) return _reply(_say('which'), rows: found.take(_rowsShown).map(_productRow).toList());
    final p = found.single;
    return _reply(
      p.counted ? _say('have', a: p.name, b: formatQty(p.quantityMilli, p.unit)) : _say('notCounted', a: p.name),
      open: (_) => ProductStockScreen(product: p),
    );
  }

  // ---------- calendar (every role) ----------

  Future<AskAnswer> _calendar(Set<Concept> about) async {
    final tomorrow = about.contains(Concept.tomorrow);
    final day = DateTime(now.year, now.month, now.day + (tomorrow ? 1 : 0));
    final events = await _get(() => app.calendar.events(role), () => app.calendarStore.loadEvents(role));
    List<Festival> festivals;
    try {
      festivals = await app.calendar.festivals();
    } on ApiException {
      festivals = await app.calendarStore.loadFestivals() ?? const [];
    }
    final rows = [
      for (final f in festivals)
        if (isSameDay(f.day, day)) AskRow(f.name),
      for (final e in events)
        if (e.occursOn(day)) AskRow(e.title, amount: e.minuteOfDay == null ? '' : timeLabel(e.minuteOfDay!)),
    ];
    final key = tomorrow ? 'tomorrow' : 'today';
    return _reply(
      rows.isEmpty ? _say('${key}None') : _say(key, a: '${rows.length}'),
      rows: rows.take(_rowsShown).toList(),
      open: switch (role) {
        QboxRole.business => openShopCalendar,
        QboxRole.customer => openCustomerCalendar,
        QboxRole.supplier => openSupplierCalendar,
      },
    );
  }

  Future<AskAnswer?> _reminder(String text, Future<String?> Function()? english) async {
    final words = _lang == AppLanguage.english ? text : await english?.call();
    if (words == null) return null;
    final draft = parseSpokenEvent(words, now, spokenTime: nativeTime(text, _lang));
    if (draft == null) return null;
    return _reply(
      _say('reminder', a: '${draft.title}, ${longDate(draft.day)}'),
      action: AskAction(
        _say('check'),
        (context) => _push(context, (_) => EventFormScreen(role: role, draft: draft, fromVoice: true, heard: text)),
      ),
    );
  }
}

/// "₹500", "₹200 advance", "₹0".
String balanceText(int paise) => paise < 0 ? '${rupees(paise.abs())} advance' : rupees(paise);

/// Words in business names that alone do not say which one.
const _common = {
  'shop', 'shops', 'store', 'stores', 'kirana', 'trader', 'traders', 'supplier', 'suppliers', 'supplies', 'general', 'and',
  'the', 'sri', 'shree', 'shri', 'new', 'mart', 'super', 'agencies', 'agency', 'enterprises', 'foods', 'company', 'co',
  // Words of questions.
  'how', 'much', 'many', 'who', 'what', 'which', 'owe', 'owes', 'due', 'dues', 'stock', 'low', 'order', 'orders',
  'payment', 'payments', 'today', 'total', 'month', 'most', 'more', 'cash', 'udhaar', 'balance', 'list', 'left', 'is',
  'my', 'me', 'do', 'in', 'customer', 'customers', 'money', 'came', 'come', 'give', 'given', 'gave', 'paid', 'sold',
  'running', 'worth', 'value', 'late', 'overdue', 'spend', 'spent', 'budget', 'calendar', 'tomorrow', 'pending', 'any',
  'product', 'products', 'goods', 'received', 'receive', 'connect', 'item', 'items', 'highest', 'this', 'have', 'has',
};

/// The ones of [all] named in [heard] (best matches only).
List<T> _named<T>(String heard, List<T> all, String Function(T) name) {
  final words = heard
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.length >= 2 && !_common.contains(w))
      .toList();
  var best = 0;
  var found = <T>[];
  for (final x in all) {
    final own = transliterate(name(x)).toLowerCase().split(RegExp(r'[^a-z]+')).where((w) => !_common.contains(w)).join(' ');
    final hits = nameHits(own, words).length;
    if (hits == 0) continue;
    if (hits > best) {
      best = hits;
      found = [x];
    } else if (hits == best) {
      found.add(x);
    }
  }
  return found;
}
