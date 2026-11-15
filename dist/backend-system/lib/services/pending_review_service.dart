import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PendingReviewRequest {
  const PendingReviewRequest({
    required this.orderId,
    required this.restaurantId,
    required this.restaurantSlug,
    this.restaurantName = '',
    this.createdAt,
  });

  final String orderId;
  final String restaurantId;
  final String restaurantSlug;
  final String restaurantName;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => {
        'orderId': orderId,
        'restaurantId': restaurantId,
        'restaurantSlug': restaurantSlug,
        'restaurantName': restaurantName,
        'createdAt': (createdAt ?? DateTime.now().toUtc()).toIso8601String(),
      };

  factory PendingReviewRequest.fromJson(Map<String, dynamic> json) {
    return PendingReviewRequest(
      orderId: json['orderId']?.toString() ?? '',
      restaurantId: json['restaurantId']?.toString() ?? '',
      restaurantSlug: json['restaurantSlug']?.toString() ?? '',
      restaurantName: json['restaurantName']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }
}

/// Remembers orders placed on this device so we can prompt for a review
/// only after the backend reports status = delivered.
class PendingReviewService {
  PendingReviewService._();
  static final PendingReviewService instance = PendingReviewService._();

  static const _prefsKey = 'pending_order_reviews_v1';
  static const _dismissedKey = 'dismissed_order_reviews_v1';

  Future<List<PendingReviewRequest>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const [];
    return raw
        .map((row) {
          try {
            return PendingReviewRequest.fromJson(
              Map<String, dynamic>.from(jsonDecode(row) as Map),
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<PendingReviewRequest>()
        .where((row) => row.orderId.isNotEmpty)
        .toList();
  }

  Future<void> enqueue(PendingReviewRequest request) async {
    if (request.orderId.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = await list();
    final next = [
      request,
      ...current.where((row) => row.orderId != request.orderId),
    ].take(20).toList();
    await prefs.setStringList(
      _prefsKey,
      next.map((row) => jsonEncode(row.toJson())).toList(),
    );
  }

  Future<void> remove(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final next =
        (await list()).where((row) => row.orderId != orderId).toList();
    await prefs.setStringList(
      _prefsKey,
      next.map((row) => jsonEncode(row.toJson())).toList(),
    );
  }

  Future<bool> wasDismissed(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getStringList(_dismissedKey) ?? const [];
    return dismissed.contains(orderId);
  }

  Future<void> markDismissed(String orderId) async {
    if (orderId.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final dismissed = {...(prefs.getStringList(_dismissedKey) ?? const [])};
    dismissed.add(orderId);
    await prefs.setStringList(_dismissedKey, dismissed.take(50).toList());
    await remove(orderId);
  }
}
