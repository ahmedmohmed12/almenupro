import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/order.dart';
import '../../providers/order_type_provider.dart';
import '../../theme/app_theme.dart';

class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  final List<String> categories;
  final String? selectedCategory;
  final ValueChanged<String?> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    final orderType = context.watch<OrderTypeProvider>();

    return Container(
      color: AppTheme.brandSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 640;

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(child: _Logo()),
                          IconButton(
                            tooltip: 'Admin dashboard',
                            onPressed: () {
                              Navigator.of(context).pushNamed('/admin');
                            },
                            icon: const Icon(Icons.dashboard_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _OrderTypeToggle(
                        value: orderType.orderType,
                        onChanged: orderType.setOrderType,
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    const _Logo(),
                    const Spacer(),
                    _OrderTypeToggle(
                      value: orderType.orderType,
                      onChanged: orderType.setOrderType,
                    ),
                    IconButton(
                      tooltip: 'Admin dashboard',
                      onPressed: () {
                        Navigator.of(context).pushNamed('/admin');
                      },
                      icon: const Icon(Icons.dashboard_outlined),
                    ),
                  ],
                );
              },
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _CategoryChip(
                  label: 'All',
                  selected: selectedCategory == null,
                  onTap: () => onCategorySelected(null),
                ),
                ...categories.map(
                  (category) => _CategoryChip(
                    label: category,
                    selected: selectedCategory == category,
                    onTap: () => onCategorySelected(category),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/app_icon.png', height: 44),
        const SizedBox(width: 10),
        RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
            children: const [
              TextSpan(
                text: 'Almenu',
                style: TextStyle(color: AppTheme.brandOrange),
              ),
              TextSpan(
                text: 'pro',
                style: TextStyle(color: AppTheme.brandMaroon),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrderTypeToggle extends StatelessWidget {
  const _OrderTypeToggle({
    required this.value,
    required this.onChanged,
  });

  final OrderType value;
  final ValueChanged<OrderType> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<OrderType>(
      segments: const [
        ButtonSegment(
          value: OrderType.delivery,
          label: Text('Delivery'),
          icon: Icon(Icons.delivery_dining_outlined),
        ),
        ButtonSegment(
          value: OrderType.pickup,
          label: Text('Pickup'),
          icon: Icon(Icons.storefront_outlined),
        ),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: AppTheme.brandOrange.withValues(alpha: 0.18),
        labelStyle: TextStyle(
          color: selected ? AppTheme.brandMaroon : AppTheme.brandBlack,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}
