import 'package:flutter/material.dart';

import '../../../models/kitchen.dart';

class PosKitchenSelector extends StatelessWidget {
  const PosKitchenSelector({
    super.key,
    required this.kitchens,
    required this.selectedId,
    required this.autoSuggestedId,
    required this.onChanged,
    this.enabled = true,
  });

  final List<Kitchen> kitchens;
  final String? selectedId;
  final String? autoSuggestedId;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (kitchens.isEmpty) return const SizedBox.shrink();

    final effectiveSelected = selectedId ?? autoSuggestedId ?? kitchens.first.id;
    final isAuto = effectiveSelected == autoSuggestedId;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'المطبخ المستهدف',
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        helperText: isAuto
            ? 'مقترح تلقائياً حسب منطقة العميل'
            : 'تجاوز يدوي — تأكد من المطبخ الصحيح',
        helperStyle: TextStyle(
          fontSize: 10,
          color: isAuto ? Colors.green.shade700 : Colors.orange.shade800,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: kitchens.any((kitchen) => kitchen.id == effectiveSelected)
              ? effectiveSelected
              : kitchens.first.id,
          isExpanded: true,
          onChanged: enabled
              ? (id) {
                  if (id != null) onChanged(id);
                }
              : null,
          items: kitchens.map((kitchen) {
            return DropdownMenuItem(
              value: kitchen.id,
              child: Row(
                children: [
                  Expanded(child: Text(kitchen.displayName)),
                  if (kitchen.id == autoSuggestedId)
                    Container(
                      margin: const EdgeInsetsDirectional.only(start: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'تلقائي',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
