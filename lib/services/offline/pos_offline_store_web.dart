import 'dart:async';
import 'dart:html' as html;
import 'dart:indexed_db';

import 'pos_offline_store.dart';

class IndexedDbPosOfflineStore implements PosOfflineStore {
  Database? _database;
  Future<Database>? _opening;

  Future<Database> _db() {
    final existing = _database;
    if (existing != null) return Future.value(existing);
    return _opening ??= _open().whenComplete(() => _opening = null);
  }

  Future<Database> _open() async {
    final factory = html.window.indexedDB;
    if (factory == null) {
      throw StateError('IndexedDB unavailable');
    }
    final db = await factory.open(
      'almenupro_pos',
      version: 1,
      onUpgradeNeeded: (event) {
        final database = event.target.result as Database;
        for (final name in const [
          'catalog',
          'active_orders',
          'sync_queue',
          'shift_state',
        ]) {
          try {
            database.createObjectStore(name, keyPath: 'id');
          } catch (_) {}
        }
      },
    );
    _database = db;
    return db;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  Future<void> _put(String store, Map<String, dynamic> record) async {
    final db = await _db();
    final tx = db.transaction(store, 'readwrite');
    await tx.objectStore(store).put(Map<String, dynamic>.from(record));
    await tx.completed;
  }

  Future<Map<String, dynamic>?> _get(String store, String id) async {
    final db = await _db();
    final tx = db.transaction(store, 'readonly');
    final value = await tx.objectStore(store).getObject(id);
    await tx.completed;
    if (value == null) return null;
    return _asMap(value);
  }

  Future<List<Map<String, dynamic>>> _getAll(String store) async {
    final db = await _db();
    final tx = db.transaction(store, 'readonly');
    final rows = <Map<String, dynamic>>[];
    await for (final cursor in tx.objectStore(store).openCursor(autoAdvance: true)) {
      rows.add(_asMap(cursor.value));
    }
    await tx.completed;
    return rows;
  }

  Future<void> _delete(String store, String id) async {
    final db = await _db();
    final tx = db.transaction(store, 'readwrite');
    await tx.objectStore(store).delete(id);
    await tx.completed;
  }

  @override
  Future<void> putCatalog(String restaurantId, List<Map<String, dynamic>> items) async {
    final db = await _db();
    final tx = db.transaction('catalog', 'readwrite');
    final store = tx.objectStore('catalog');
    await for (final cursor in store.openCursor(autoAdvance: true)) {
      final row = _asMap(cursor.value);
      if (row['restaurantId'] == restaurantId) {
        await cursor.delete();
      }
    }
    for (final item in items) {
      final itemId = item['id']?.toString() ?? '';
      await store.put({
        ...item,
        'id': '$restaurantId:$itemId',
        'itemId': itemId,
        'restaurantId': restaurantId,
      });
    }
    await tx.completed;
  }

  @override
  Future<List<Map<String, dynamic>>> getCatalog(String restaurantId) async {
    final rows = await _getAll('catalog');
    return rows.where((row) => row['restaurantId'] == restaurantId).toList();
  }

  @override
  Future<void> putActiveOrder(Map<String, dynamic> record) =>
      _put('active_orders', record);

  @override
  Future<Map<String, dynamic>?> getActiveOrder(String id) =>
      _get('active_orders', id);

  @override
  Future<List<Map<String, dynamic>>> listActiveOrders(String restaurantId) async {
    final rows = await _getAll('active_orders');
    return rows.where((row) => row['restaurantId'] == restaurantId).toList();
  }

  @override
  Future<void> deleteActiveOrder(String id) => _delete('active_orders', id);

  @override
  Future<void> putQueueItem(Map<String, dynamic> record) =>
      _put('sync_queue', record);

  @override
  Future<List<Map<String, dynamic>>> listQueuePending() async {
    final rows = await _getAll('sync_queue');
    final pending = rows.where((row) => row['status'] != 'synced').toList();
    pending.sort(
      (a, b) => (a['createdAt']?.toString() ?? '').compareTo(b['createdAt']?.toString() ?? ''),
    );
    return pending;
  }

  @override
  Future<void> deleteQueueItem(String id) => _delete('sync_queue', id);

  @override
  Future<void> putShiftState(Map<String, dynamic> record) =>
      _put('shift_state', record);

  @override
  Future<Map<String, dynamic>?> getShiftState(String id) =>
      _get('shift_state', id);
}

PosOfflineStore createPosOfflineStore() => IndexedDbPosOfflineStore();
