import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class TableQrCategoryNav extends StatelessWidget {
  const TableQrCategoryNav({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
    required this.scrollController,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final active = category == selected;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: ChoiceChip(
              selected: active,
              label: Text(category),
              labelStyle: TextStyle(
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppTheme.brandMaroon,
                fontSize: 13,
              ),
              selectedColor: AppTheme.brandOrange,
              backgroundColor: Colors.white,
              side: BorderSide(
                color: active
                    ? AppTheme.brandOrange
                    : AppTheme.brandMaroon.withValues(alpha: 0.2),
              ),
              onSelected: (_) => onSelected(category),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          );
        },
      ),
    );
  }
}
