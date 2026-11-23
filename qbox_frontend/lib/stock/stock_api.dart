import '../services/api_client.dart';
import 'stock_models.dart';

/// Everything the app asks the backend about stock. Needs login (shop).
abstract class StockApi {
  Future<StockBook> stock();

  Future<StockItem> addItem(ItemDraft draft);

  /// Many items at once (quick start). Names already in stock are skipped.
  Future<List<StockItem>> addItems(List<ItemDraft> drafts);

  Future<ItemDetail> item(int id);

  Future<StockItem> changeItem(int id, {required String name, int? costPaise, int? pricePaise, int? alertMilli});

  /// Removes the item from the list; its history is kept.
  Future<StockItem> archiveItem(int id);

  Future<StockMove> addMove(int itemId, MoveDraft draft);
}

class HttpStockApi implements StockApi {
  HttpStockApi(this._api);

  final ApiClient _api;

  static const _base = '/api/stock/items';

  @override
  Future<StockBook> stock() async => _read(await _api.get(_base), StockBook.fromJson);

  @override
  Future<StockItem> addItem(ItemDraft draft) async =>
      _read(await _api.post(_base, draft.toJson()), StockItem.fromJson);

  @override
  Future<List<StockItem>> addItems(List<ItemDraft> drafts) async {
    final json = await _api.post('$_base/bulk', {
      'items': [for (final d in drafts) d.toJson()],
    });
    return json is List ? json.map(StockItem.fromJson).whereType<StockItem>().toList() : <StockItem>[];
  }

  @override
  Future<ItemDetail> item(int id) async => _read(await _api.get('$_base/$id'), ItemDetail.fromJson);

  @override
  Future<StockItem> changeItem(int id, {required String name, int? costPaise, int? pricePaise, int? alertMilli}) async =>
      _read(
        await _api.put('$_base/$id', {
          'name': name.trim(),
          'costPaise': costPaise,
          'pricePaise': pricePaise,
          'alertMilli': alertMilli,
        }),
        StockItem.fromJson,
      );

  @override
  Future<StockItem> archiveItem(int id) async =>
      _read(await _api.post('$_base/$id/archive', {}), StockItem.fromJson);

  @override
  Future<StockMove> addMove(int itemId, MoveDraft draft) async =>
      _read(await _api.post('$_base/$itemId/moves', draft.toJson()), StockMove.fromJson);

  static T _read<T>(Object? json, T? Function(Object?) read) {
    final value = read(json);
    if (value == null) {
      throw const ApiException('ERROR', 'Something went wrong. Please try again.');
    }
    return value;
  }
}
