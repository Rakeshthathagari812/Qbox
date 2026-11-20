import '../services/api_client.dart';
import 'udhaar_models.dart';

/// Everything the app asks the backend about udhaar. Needs login.
abstract class UdhaarApi {
  // Shop side
  Future<UdhaarBook> book();

  Future<InviteSent> sendInvite(String name, String mobile);

  Future<UdhaarCustomer> addCustomer({
    required String name,
    required String mobile,
    required String otp,
    int? creditLimitPaise,
  });

  Future<CustomerDetail> customer(int id);

  Future<UdhaarCustomer> changeCustomer(
    int id, {
    required String name,
    int? creditLimitPaise,
  });

  Future<UdhaarEntry> addEntry(int customerId, EntryDraft draft);

  Future<UdhaarEntry> deleteEntry(int entryId, String reason);

  /// Change a customer's number: a code goes to the new number first.
  Future<InviteSent> sendNumberInvite(int customerId, String mobile);

  Future<UdhaarCustomer> changeNumber(int customerId, String mobile, String otp);

  /// "Not me" report: the number IS the customer's (link stays).
  Future<UdhaarCustomer> confirmDispute(int customerId);

  /// "Not me" report: wrong number (book hidden from that phone).
  Future<UdhaarCustomer> unlinkDispute(int customerId);

  // Customer side
  Future<List<MyBook>> myBooks();

  Future<MyBookDetail> myBook(int bookId);

  /// Reports "this is not my number". Nothing is hidden; the shop decides.
  Future<MyBook> notMe(int bookId);

  /// Takes the report back (before the shop decides).
  Future<MyBook> cancelNotMe(int bookId);
}

class HttpUdhaarApi implements UdhaarApi {
  HttpUdhaarApi(this._api);

  final ApiClient _api;

  static const _base = '/api/udhaar';

  @override
  Future<UdhaarBook> book() async =>
      _read(await _api.get('$_base/customers'), UdhaarBook.fromJson);

  @override
  Future<InviteSent> sendInvite(String name, String mobile) async {
    final json = await _api.post('$_base/customers/otp', {
      'name': name,
      'mobile': mobile,
    });
    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    return InviteSent(
      resendInSeconds: map['resendInSeconds'] as int? ?? 30,
      devOtp: map['devOtp'] as String?,
    );
  }

  @override
  Future<UdhaarCustomer> addCustomer({
    required String name,
    required String mobile,
    required String otp,
    int? creditLimitPaise,
  }) async => _read(
    await _api.post('$_base/customers', {
      'name': name,
      'mobile': mobile,
      'otp': otp,
      'creditLimitPaise': creditLimitPaise,
    }),
    UdhaarCustomer.fromJson,
  );

  @override
  Future<CustomerDetail> customer(int id) async =>
      _read(await _api.get('$_base/customers/$id'), CustomerDetail.fromJson);

  @override
  Future<UdhaarCustomer> changeCustomer(
    int id, {
    required String name,
    int? creditLimitPaise,
  }) async => _read(
    await _api.put('$_base/customers/$id', {
      'name': name,
      'creditLimitPaise': creditLimitPaise,
    }),
    UdhaarCustomer.fromJson,
  );

  @override
  Future<UdhaarEntry> addEntry(int customerId, EntryDraft draft) async => _read(
    await _api.post('$_base/customers/$customerId/entries', draft.toJson()),
    UdhaarEntry.fromJson,
  );

  @override
  Future<UdhaarEntry> deleteEntry(int entryId, String reason) async => _read(
    await _api.post('$_base/entries/$entryId/delete', {'reason': reason}),
    UdhaarEntry.fromJson,
  );

  @override
  Future<List<MyBook>> myBooks() async {
    final json = await _api.get('$_base/mine');
    return json is List
        ? json.map(MyBook.fromJson).whereType<MyBook>().toList()
        : <MyBook>[];
  }

  @override
  Future<MyBookDetail> myBook(int bookId) async =>
      _read(await _api.get('$_base/mine/$bookId'), MyBookDetail.fromJson);

  @override
  Future<MyBook> notMe(int bookId) async =>
      _read(await _api.post('$_base/mine/$bookId/not-me', {}), MyBook.fromJson);

  @override
  Future<MyBook> cancelNotMe(int bookId) async =>
      _read(await _api.post('$_base/mine/$bookId/not-me/cancel', {}), MyBook.fromJson);

  @override
  Future<InviteSent> sendNumberInvite(int customerId, String mobile) async {
    final json = await _api.post('$_base/customers/$customerId/number/otp', {'mobile': mobile});
    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    return InviteSent(
      resendInSeconds: map['resendInSeconds'] as int? ?? 30,
      devOtp: map['devOtp'] as String?,
    );
  }

  @override
  Future<UdhaarCustomer> changeNumber(int customerId, String mobile, String otp) async => _read(
    await _api.post('$_base/customers/$customerId/number', {'mobile': mobile, 'otp': otp}),
    UdhaarCustomer.fromJson,
  );

  @override
  Future<UdhaarCustomer> confirmDispute(int customerId) async => _read(
    await _api.post('$_base/customers/$customerId/dispute/confirm', {}),
    UdhaarCustomer.fromJson,
  );

  @override
  Future<UdhaarCustomer> unlinkDispute(int customerId) async => _read(
    await _api.post('$_base/customers/$customerId/dispute/unlink', {}),
    UdhaarCustomer.fromJson,
  );

  static T _read<T>(Object? json, T? Function(Object?) read) {
    final value = read(json);
    if (value == null) {
      throw const ApiException('ERROR', 'Something went wrong. Please try again.');
    }
    return value;
  }
}
