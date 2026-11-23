import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/api_client.dart';
import 'stock_api.dart';
import 'stock_models.dart';
import 'stock_store.dart';

enum MoveSaved {
  /// On the server.
  saved,

  /// No internet: kept on the phone, sent automatically later.
  savedOffline,
}

/// What happened when the waiting moves were sent.
class StockSyncReport {
  const StockSyncReport({this.sent = 0, this.refused = const [], this.waiting = 0});

  final int sent;

  /// Moves the server would not take (shown to the shopkeeper, then dropped).
  final List<String> refused;
  final int waiting;
}

/// The stock for the screens: the server copy, the phone copy for offline
/// use, and the queue of moves saved while offline. Each move carries its own
/// id made on the phone (clientRef), so a retried sending is kept only once.
class StockRepository {
  StockRepository(this.api, this.store);

  final StockApi api;
  final StockStore store;

  /// Items running low, for the red badge on the home screen's Stock tile.
  final ValueNotifier<int> lowCount = ValueNotifier(0);

  Future<StockSyncReport>? _sending;

  /// The phone copy, including moves not sent yet. Null if never loaded.
  Future<StockBook?> savedBook() async {
    final book = await store.loadBook();
    return book == null ? null : _counted(_bookWithPending(book, await store.loadPending()));
  }

  /// Sends waiting moves, then gets the latest stock. Throws [ApiException].
  Future<StockBook> freshBook() async {
    await sendPending();
    final book = await api.stock();
    await store.saveBook(book);
    return _counted(_bookWithPending(book, await store.loadPending()));
  }

  StockBook _counted(StockBook book) {
    lowCount.value = book.lowCount;
    return book;
  }

  /// The phone copy of one item (its line in the saved list if its page was
  /// never opened online). Null if neither is saved.
  Future<ItemDetail?> savedItem(int id) async {
    var detail = await store.loadItem(id);
    if (detail == null) {
      final inBook = (await store.loadBook())?.items.where((i) => i.id == id).firstOrNull;
      if (inBook == null) return null;
      detail = ItemDetail(item: inBook, moves: const []);
    }
    return _detailWithPending(detail, await store.loadPending());
  }

  Future<ItemDetail> freshItem(int id) async {
    await sendPending();
    final detail = await api.item(id);
    await store.saveItem(detail);
    return _detailWithPending(detail, await store.loadPending());
  }

  /// Saves on the server, or on the phone when there is no internet.
  Future<MoveSaved> addMove(int itemId, MoveDraft draft) async {
    await sendPending(); // keep moves in the order they were made
    try {
      await api.addMove(itemId, draft);
      return MoveSaved.saved;
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      final pending = await store.loadPending()..add(PendingMove(itemId: itemId, draft: draft));
      await store.savePending(pending);
      return MoveSaved.savedOffline;
    }
  }

  Future<int> pendingCount() async => (await store.loadPending()).length;

  /// Sends the moves saved while offline, oldest first. Stops quietly at the
  /// first network problem; they stay on the phone for next time.
  Future<StockSyncReport> sendPending() => _sending ??= _send().whenComplete(() => _sending = null);

  Future<StockSyncReport> _send() async {
    var sent = 0;
    final refused = <String>[];
    var pending = await store.loadPending();
    while (pending.isNotEmpty) {
      final next = pending.first;
      try {
        await api.addMove(next.itemId, next.draft);
        sent++;
      } on ApiException catch (e) {
        if (e.isNetwork || e.isUnauthorized) break;
        refused.add(e.message); // e.g. the item was removed: drop it
      }
      pending = await store.loadPending()..removeWhere((p) => p.draft.clientRef == next.draft.clientRef);
      await store.savePending(pending);
    }
    return StockSyncReport(sent: sent, refused: refused, waiting: pending.length);
  }

  // Adding and changing items needs internet (each item gets its id from the server).

  Future<StockItem> addItem(ItemDraft draft) => api.addItem(draft);

  Future<List<StockItem>> addItems(List<ItemDraft> drafts) => api.addItems(drafts);

  Future<StockItem> changeItem(int id, {required String name, int? costPaise, int? pricePaise, int? alertMilli}) =>
      api.changeItem(id, name: name, costPaise: costPaise, pricePaise: pricePaise, alertMilli: alertMilli);

  Future<StockItem> archiveItem(int id) => api.archiveItem(id);

  /// Log out: forget the stock and anything not sent.
  Future<void> clear() {
    lowCount.value = 0;
    return store.clear();
  }

  // ---------- adding waiting moves to what is shown ----------

  static StockBook _bookWithPending(StockBook book, List<PendingMove> pending) {
    if (pending.isEmpty) return book;
    return StockBook([for (final i in book.items) _itemWithPending(i, pending)], pastItems: book.pastItems);
  }

  static StockItem _itemWithPending(StockItem item, List<PendingMove> pending, {Set<String> skip = const {}}) {
    var quantity = item.quantityMilli;
    var last = item.lastMoveAt;
    for (final p in pending) {
      if (p.itemId != item.id || skip.contains(p.draft.clientRef)) continue;
      quantity += StockMove.pending(p.draft).effect;
      if (last == null || p.draft.moveAt.isAfter(last)) last = p.draft.moveAt;
    }
    return item.copyWith(quantityMilli: quantity, lastMoveAt: last);
  }

  static ItemDetail _detailWithPending(ItemDetail detail, List<PendingMove> pending) {
    final known = {for (final m in detail.moves) m.clientRef};
    final waiting = [
      for (final p in pending)
        if (p.itemId == detail.item.id && !known.contains(p.draft.clientRef)) StockMove.pending(p.draft),
    ]..sort((a, b) => b.moveAt.compareTo(a.moveAt));
    if (waiting.isEmpty) return detail;
    return ItemDetail(
      item: _itemWithPending(detail.item, pending, skip: known),
      moves: [...waiting, ...detail.moves],
    );
  }
}
