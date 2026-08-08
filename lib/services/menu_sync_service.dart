import 'dart:convert';

import 'package:flutter/material.dart';

import 'menu_storage_service.dart';

Future<void> syncAndAddNewItems({
  required List<Map<String, dynamic>> incomingItems,
  required void Function(int addedCount, int skippedCount, int updatedCount)
      onComplete,
  void Function(int totalCount)? onTotalCount,
  bool updateExisting = false,
  String? sourceUrl,
}) async {
  try {
    final result = await MenuStorageService.instance.syncItems(
      incomingItems: incomingItems,
      updateExisting: updateExisting,
      sourceUrl: sourceUrl,
    );
    onComplete(result.addedCount, result.skippedCount, result.updatedCount);
    onTotalCount?.call(result.totalCount);
  } catch (error) {
    debugPrint('خطأ أثناء مزامنة المنيو: $error');
    onComplete(0, 0, 0);
  }
}

List<Map<String, dynamic>> flattenMenuCategories(
  List<Map<String, dynamic>> categories, {
  String source = 'Talabat',
}) {
  final flattened = <Map<String, dynamic>>[];

  for (final category in categories) {
    final categoryName = category['categoryName'] as String? ?? 'عام';
    for (final rawItem in category['items'] as List<dynamic>? ?? []) {
      if (rawItem is! Map<String, dynamic>) continue;
      flattened.add({
        'name': rawItem['name'],
        'description': rawItem['description'] ?? '',
        'price': rawItem['price'] ?? 0.0,
        'categoryName': categoryName,
        'isAvailable': rawItem['isAvailable'] ?? true,
        'imageUrl': rawItem['imageUrl'] ?? '',
        'source': source,
      });
    }
  }

  return flattened;
}

List<Map<String, dynamic>> parseMenuInput(String rawInput) {
  final trimmed = rawInput.trim();
  if (trimmed.isEmpty) return [];

  try {
    final decoded = jsonDecode(trimmed);

    if (decoded is List) {
      if (decoded.isEmpty) return [];

      final first = decoded.first;
      if (first is Map && first.containsKey('items')) {
        return flattenMenuCategories(
          decoded
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList(),
          source: 'Import',
        );
      }

      return decoded
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .where((item) => (item['name'] ?? '').toString().trim().isNotEmpty)
          .map(
            (item) => {
              'name': item['name'],
              'description': item['description'] ?? '',
              'price': item['price'] ?? 0.0,
              'categoryName': item['categoryName'] ?? 'أصناف جديدة',
              'isAvailable': item['isAvailable'] ?? true,
              'imageUrl': item['imageUrl'] ?? '',
              'source': item['source'] ?? 'Import',
            },
          )
          .toList();
    }

    if (decoded is Map && decoded.containsKey('items')) {
      return flattenMenuCategories([Map<String, dynamic>.from(decoded)]);
    }
  } catch (error) {
    debugPrint('Parsing error: $error');
  }

  return [];
}
