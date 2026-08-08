import 'package:flutter/material.dart';

import 'admin_menu_item_picker.dart';

class AdminItemLinkedSidesEditor extends StatelessWidget {
  const AdminItemLinkedSidesEditor({
    super.key,
    required this.linkedItemIds,
    required this.onChanged,
    this.currentItemId,
  });

  final List<int> linkedItemIds;
  final ValueChanged<List<int>> onChanged;
  final int? currentItemId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'السايد إيتمز المقترحة تلقائياً',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AdminMenuItemPicker.burgundy,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'اربط أصنافاً فرعية تُعرض للعميل مع هذا المنتج وفي اقتراحات السلة.',
          style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
        ),
        const SizedBox(height: 10),
        AdminMenuItemPicker(
          selectedIds: linkedItemIds,
          excludeIds: currentItemId != null ? {currentItemId!} : const {},
          onChanged: onChanged,
          label: 'أصناف مقترحة مع هذا المنتج',
        ),
      ],
    );
  }
}
