import 'dart:async';
import 'dart:html' as html;
import 'dart:indexed_db';

import 'table_floor_cache.dart';

class IndexedDbTableFloorCache implements TableFloorCache {
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
      'almenupro_table_floor',
      version: 1,
      onUpgradeNeeded: (event) {
        final database = event.target.result as Database;
        try {
          database.createObjectStore('table_floor', keyPath: 'id');
        } catch (_) {}
      },
    );
    _database = db;
    return db;
  }

  @override
  Future<void> save(String restaurantId, List<Map<String, dynamic>> tables) async {
    final db = await _db();
    final tx = db.transaction('table_floor', 'readwrite');
    final store = tx.objectStore('table_floor');
    await store.put({
      'id': restaurantId,
      'restaurantId': restaurantId,
      'tables': tables,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await tx.completed;
  }

  @override
  Future<List<Map<String, dynamic>>> load(String restaurantId) async {
    try {
      final db = await _db();
      final tx = db.transaction('table_floor', 'readonly');
      final raw = await tx.objectStore('table_floor').getObject(restaurantId);
      await tx.completed;
      if (raw is Map && raw['tables'] is List) {
        return (raw['tables'] as List)
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList();
      }
    } catch (_) {}
    return const [];
  }
}

TableFloorCache createTableFloorCache() => IndexedDbTableFloorCache();
