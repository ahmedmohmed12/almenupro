import 'package:flutter/material.dart';

/// Foodics-inspired palette for inventory module (RTL admin).
abstract final class InventoryTheme {
  static const burgundy = Color(0xFF6D1A36);
  static const accent = Color(0xFFFFA726);
  static const surface = Color(0xFFF8F4F5);
  static const draft = Color(0xFF5C6BC0);
  static const closed = Color(0xFF2E7D32);

  static ChipStatusColors statusColors(String status) {
    final s = status.toUpperCase();
    if (s == 'DRAFT') {
      return const ChipStatusColors(
        bg: Color(0xFFE8EAF6),
        fg: draft,
        label: 'مسودة',
      );
    }
    if (s == 'CLOSED' || s == 'APPROVED') {
      return const ChipStatusColors(
        bg: Color(0xFFE8F5E9),
        fg: closed,
        label: 'مغلق',
      );
    }
    return ChipStatusColors(
      bg: Colors.grey.shade200,
      fg: Colors.grey.shade800,
      label: status,
    );
  }
}

class ChipStatusColors {
  const ChipStatusColors({
    required this.bg,
    required this.fg,
    required this.label,
  });

  final Color bg;
  final Color fg;
  final String label;
}

class InventoryDocStatusChip extends StatelessWidget {
  const InventoryDocStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = InventoryTheme.statusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        colors.label,
        style: TextStyle(color: colors.fg, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class InventoryStockBadge extends StatelessWidget {
  const InventoryStockBadge({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final c = code.toUpperCase();
    Color bg = Colors.green.shade50;
    Color fg = Colors.green.shade800;
    String label = 'متوفر';
    if (c == 'LOW') {
      bg = const Color(0xFFFFF3E0);
      fg = InventoryTheme.accent;
      label = 'منخفض';
    } else if (c == 'OUT') {
      bg = Colors.red.shade50;
      fg = Colors.red.shade800;
      label = 'نفد';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}