import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences cart/pending drafts shared by Web + Native.
///
/// Web also keeps IndexedDB via [PosOfflineStore]; Native uses prefs-backed
/// [PrefsPosOfflineStore] (Hive/Isar can replace that store later).
abstract final class PosLocalDrafts {
  static const _cartPrefix = 'pos_cart_draft_v1:';
  static const _pendingKey = 'pos_pending_orders_v1';

  static String _cartKey(String restaurantId, String cartId) =>
      '$_cartPrefix${restaurantId.trim()}|$cartId';

  static Future<void> saveCartDraft({
    required String restaurantId,
    required String cartId,
    required List<Map<String, dynamic>> cartItems,
    String customerName = '',
    String phone = '',
    String paymentMethod = '',
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _cartKey(restaurantId, cartId);
      if (cartItems.isEmpty) {
        await prefs.remove(key);
        return;
      }
      await prefs.setString(
        key,
        jsonEncode({
          'id': cartId,
          'restaurantId': restaurantId,
          'cartItems': cartItems,
          'customerName': customerName,
          'phone': phone,
          'paymentMethod': paymentMethod,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } catch (error) {
      debugPrint('POS cart draft save skipped: $error');
    }
  }

  static Future<Map<String, dynamic>?> loadCartDraft({
    required String restaurantId,
    required String cartId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cartKey(restaurantId, cartId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearCartDraft({
    required String restaurantId,
    required String cartId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cartKey(restaurantId, cartId));
    } catch (_) {}
  }

  static Future<void> upsertPendingOrder(Map<String, dynamic> record) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = await listPendingOrders();
      final id = record['id']?.toString() ?? '';
      if (id.isEmpty) return;
      final next = [
        ...pending.where((row) => row['id']?.toString() != id),
        Map<String, dynamic>.from(record),
      ];
      await prefs.setString(_pendingKey, jsonEncode(next));
    } catch (error) {
      debugPrint('POS pending draft save skipped: $error');
    }
  }

  static Future<List<Map<String, dynamic>>> listPendingOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<void> removePendingOrder(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = await listPendingOrders();
      final next =
          pending.where((row) => row['id']?.toString() != id).toList();
      if (next.isEmpty) {
        await prefs.remove(_pendingKey);
      } else {
        await prefs.setString(_pendingKey, jsonEncode(next));
      }
    } catch (_) {}
  }
}
