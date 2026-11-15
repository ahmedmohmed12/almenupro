import 'package:flutter/widgets.dart';

import '../../models/menu_item.dart';

/// Shared catalog matching used by POS search + barcode listeners (Web/Native).

bool posMatchesSearch(MenuItem item, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;

  if (item.talabatId?.toString() == q || item.id.toString() == q) {
    return true;
  }

  final names = [
    item.name.toLowerCase(),
    item.nameAr.toLowerCase(),
    item.nameEn.toLowerCase(),
  ];

  for (final name in names) {
    if (name.startsWith(q) || name.contains(q)) return true;
    final initials = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.characters.first)
        .join();
    if (initials.startsWith(q)) return true;
  }
  return false;
}

MenuItem? posFindBarcodeMatch(List<MenuItem> items, String query) {
  final q = query.trim();
  if (q.isEmpty) return null;
  for (final item in items) {
    if (item.talabatId?.toString() == q || item.id.toString() == q) {
      return item;
    }
  }
  return null;
}
