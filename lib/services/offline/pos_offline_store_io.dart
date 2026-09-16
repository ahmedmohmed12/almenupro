import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pos_offline_store.dart';

/// Native desktop offline store backed by SharedPreferences JSON maps.
///
/// Swap the internals for Hive/Isar later without changing [PosOfflineStore]
/// callers — keep key namespaces stable when migrating.
class PrefsPosOfflineStore implements PosOfflineStore {
  static const _catalogKey = 'pos_native_catalog_v1';
  static const _activeKey = 'pos_native_active_v1';
  static const _queueKey = 'pos_native_queue_v1';
  static const _shiftKey = 'pos_native_shift_v1';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<Map<String, Map<String, dynamic>>> _readMap(String key) async {
    try {
      final raw = (await _prefs).getString(key);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, Map<String, dynamic>>{};
      decoded.forEach((k, v) {
        if (v is Map) out[k.toString()] = Map<String, dynamic>.from(v);
      });
      return out;
    } catch (error) {
      debugPrint('POS native store read failed ($key): $error');
      return {};
    }
  }

  Future<void> _writeMap(
    String key,
    Map<String, Map<String, dynamic>> value,
  ) async {
    try {
      await (await _prefs).setString(key, jsonEncode(value));
    } catch (error) {
      debugPrint('POS native store write failed ($key): $error');
    }
  }

  @override
  Future<void> putCatalog(
    String restaurantId,
    List<Map<String, dynamic>> items,
  ) async {
    final all = await _readMap(_catalogKey);
    all.removeWhere((_, row) => row['restaurantId'] == restaurantId);
    for (final item in items) {
      final itemId = item['id']?.toString() ?? '';
      final id = '$restaurantId:$itemId';
      all[id] = {
        ...item,
        'id': id,
        'itemId': itemId,
        'restaurantId': restaurantId,
      };
    }
    await _writeMap(_catalogKey, all);
  }

  @override
  Future<List<Map<String, dynamic>>> getCatalog(String restaurantId) async {
    final all = await _readMap(_catalogKey);
    return all.values
        .where((row) => row['restaurantId'] == restaurantId)
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
  }

  @override
  Future<void> putActiveOrder(Map<String, dynamic> record) async {
    final all = await _readMap(_activeKey);
    all[record['id'].toString()] = Map<String, dynamic>.from(record);
    await _writeMap(_activeKey, all);
  }

  @override
  Future<Map<String, dynamic>?> getActiveOrder(String id) async {
    final all = await _readMap(_activeKey);
    final row = all[id];
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  @override
  Future<List<Map<String, dynamic>>> listActiveOrders(
    String restaurantId,
  ) async {
    final all = await _readMap(_activeKey);
    return all.values
        .where((row) => row['restaurantId'] == restaurantId)
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
  }

  @override
  Future<void> deleteActiveOrder(String id) async {
    final all = await _readMap(_activeKey);
    all.remove(id);
    await _writeMap(_activeKey, all);
  }

  @override
  Future<void> putQueueItem(Map<String, dynamic> record) async {
    final all = await _readMap(_queueKey);
    all[record['id'].toString()] = Map<String, dynamic>.from(record);
    await _writeMap(_queueKey, all);
  }

  @override
  Future<List<Map<String, dynamic>>> listQueuePending() async {
    final all = await _readMap(_queueKey);
    final rows = all.values
        .where((row) => row['status'] != 'synced')
        .map(Map<String, dynamic>.from)
        .toList();
    rows.sort(
      (a, b) => (a['createdAt']?.toString() ?? '')
          .compareTo(b['createdAt']?.toString() ?? ''),
    );
    return rows;
  }

  @override
  Future<void> deleteQueueItem(String id) async {
    final all = await _readMap(_queueKey);
    all.remove(id);
    await _writeMap(_queueKey, all);
  }

  @override
  Future<void> putShiftState(Map<String, dynamic> record) async {
    final all = await _readMap(_shiftKey);
    all[record['id'].toString()] = Map<String, dynamic>.from(record);
    await _writeMap(_shiftKey, all);
  }

  @override
  Future<Map<String, dynamic>?> getShiftState(String id) async {
    final all = await _readMap(_shiftKey);
    final row = all[id];
    return row == null ? null : Map<String, dynamic>.from(row);
  }
}

PosOfflineStore createPosOfflineStore() => PrefsPosOfflineStore();
