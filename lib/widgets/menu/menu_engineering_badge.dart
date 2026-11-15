import 'package:flutter/material.dart';

import '../../models/menu_item.dart';
import '../../theme/app_theme.dart';

class MenuEngineeringBadge extends StatelessWidget {
  const MenuEngineeringBadge({super.key, required this.label, this.compact = false});

  final String label;
  final bool compact;

  factory MenuEngineeringBadge.forItem(MenuItem item, {bool compact = false}) {
    final text = item.catalogBadge?.trim() ?? '';
    return MenuEngineeringBadge(label: text, compact: compact);
  }

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: AppTheme.brandMaroon.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: compact ? 10 : 11,
        ),
      ),
    );
  }
}
