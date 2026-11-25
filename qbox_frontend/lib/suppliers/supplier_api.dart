import '../services/api_client.dart';
import 'supplier_models.dart';

/// Everything the app asks the backend about suppliers. Needs login (shop).
abstract class SupplierApi {
  Future<SupplierBook> suppliers();

  /// Adding, step 1: a code goes to the supplier's phone.
  Future<SupplierCode> sendNewCode({required String name, required String mobile});

  /// With [otp] (the code they read out) the two are connected at once.
  Future<Supplier> addSupplier({required String name, String? mobile, String? supplies, String? note, String? otp, required String clientRef});

  Future<SupplierDetail> supplier(int id);

  Future<Supplier> changeSupplier(int id, {required String name, String? mobile, String? supplies, String? note});

  Future<Supplier> archiveSupplier(int id);

  /// Connecting with a supplier in the list: a code, and what the shop owes.
  Future<SupplierCode> sendCode(int id);

  Future<Supplier> verify(int id, String otp);

  /// What a connected supplier sells.
  Future<List<SupplierProduct>> products(int id);

  /// A connected supplier's own UPI ID.
  Future<SupplierPay> payInfo(int id);

  /// Disconnects, or takes the question back.
  Future<Supplier> disconnect(int id);

  Future<SupplierEntry> addEntry(int supplierId, SupplierEntryDraft draft);

  Future<SupplierEntry> deleteEntry(int entryId, String reason);

  /// Answers about what a connected supplier wrote.
  Future<SupplierEntry> confirmEntry(int entryId);

  Future<SupplierEntry> disputeEntry(int entryId, String reason);

  Future<SupplierOrder> addOrder(
    int supplierId,
    List<EntryLine> lines, {
    String note,
    PayPlan? payPlan,
    DateTime? payBy,
    required String clientRef,
  });

  /// The order's goods came: [lines] is what actually came.
  Future<SupplierOrder> receiveOrder(int orderId, SupplierEntryDraft purchase);

  Future<SupplierOrder> cancelOrder(int orderId);
}

class HttpSupplierApi implements SupplierApi {
  HttpSupplierApi(this._api);

  final ApiClient _api;

  static const _base = '/api/suppliers';

  @override
  Future<SupplierBook> suppliers() async => _read(await _api.get(_base), SupplierBook.fromJson);

  @override
  Future<SupplierCode> sendNewCode({required String name, required String mobile}) async =>
      _read(await _api.post('$_base/otp', {'name': name, 'mobile': mobile}), SupplierCode.fromJson);

  @override
  Future<Supplier> addSupplier({required String name, String? mobile, String? supplies, String? note, String? otp, required String clientRef}) async =>
      _read(
        await _api.post(_base, {
          'name': name,
          'mobile': mobile,
          'supplies': supplies,
          'note': note,
          'otp': otp,
          'clientRef': clientRef,
        }),
        Supplier.fromJson,
      );

  @override
  Future<SupplierDetail> supplier(int id) async => _read(await _api.get('$_base/$id'), SupplierDetail.fromJson);

  @override
  Future<Supplier> changeSupplier(int id, {required String name, String? mobile, String? supplies, String? note}) async =>
      _read(
        await _api.put('$_base/$id', {'name': name, 'mobile': mobile, 'supplies': supplies, 'note': note}),
        Supplier.fromJson,
      );

  @override
  Future<Supplier> archiveSupplier(int id) async => _read(await _api.post('$_base/$id/archive', {}), Supplier.fromJson);

  @override
  Future<SupplierCode> sendCode(int id) async => _read(await _api.post('$_base/$id/otp', {}), SupplierCode.fromJson);

  @override
  Future<Supplier> verify(int id, String otp) async =>
      _read(await _api.post('$_base/$id/verify', {'otp': otp}), Supplier.fromJson);

  @override
  Future<List<SupplierProduct>> products(int id) async => _read(
    await _api.get('$_base/$id/products'),
    (json) => json is List ? json.map(SupplierProduct.fromJson).whereType<SupplierProduct>().toList() : null,
  );

  @override
  Future<SupplierPay> payInfo(int id) async => _read(await _api.get('$_base/$id/pay'), SupplierPay.fromJson);

  @override
  Future<Supplier> disconnect(int id) async => _read(await _api.post('$_base/$id/disconnect', {}), Supplier.fromJson);

  @override
  Future<SupplierEntry> addEntry(int supplierId, SupplierEntryDraft draft) async =>
      _read(await _api.post('$_base/$supplierId/entries', draft.toJson()), SupplierEntry.fromJson);

  @override
  Future<SupplierEntry> deleteEntry(int entryId, String reason) async =>
      _read(await _api.post('$_base/entries/$entryId/delete', {'reason': reason}), SupplierEntry.fromJson);

  @override
  Future<SupplierEntry> confirmEntry(int entryId) async =>
      _read(await _api.post('$_base/entries/$entryId/confirm', {}), SupplierEntry.fromJson);

  @override
  Future<SupplierEntry> disputeEntry(int entryId, String reason) async =>
      _read(await _api.post('$_base/entries/$entryId/dispute', {'reason': reason}), SupplierEntry.fromJson);

  @override
  Future<SupplierOrder> addOrder(
    int supplierId,
    List<EntryLine> lines, {
    String note = '',
    PayPlan? payPlan,
    DateTime? payBy,
    required String clientRef,
  }) async =>
      _read(
        await _api.post('$_base/$supplierId/orders', {
          'lines': [for (final l in lines) l.toInput()],
          'note': note.trim().isEmpty ? null : note.trim(),
          'payPlan': payPlan?.code,
          'payBy': payBy == null ? null : dayText(payBy),
          'clientRef': clientRef,
        }),
        SupplierOrder.fromJson,
      );

  @override
  Future<SupplierOrder> receiveOrder(int orderId, SupplierEntryDraft p) async => _read(
    await _api.post('$_base/orders/$orderId/receive', {
      'amountPaise': p.amountPaise,
      'lines': [for (final l in p.lines) l.toInput()],
      'paidNow': p.paidNow,
      'method': p.method?.code,
      'dueDate': p.dueDate == null ? null : dayText(p.dueDate!),
      'note': p.note.trim().isEmpty ? null : p.note.trim(),
      'clientRef': p.clientRef,
    }),
    SupplierOrder.fromJson,
  );

  @override
  Future<SupplierOrder> cancelOrder(int orderId) async =>
      _read(await _api.post('$_base/orders/$orderId/cancel', {}), SupplierOrder.fromJson);

  static T _read<T>(Object? json, T? Function(Object?) read) {
    final value = read(json);
    if (value == null) {
      throw const ApiException('ERROR', 'Something went wrong. Please try again.');
    }
    return value;
  }
}
