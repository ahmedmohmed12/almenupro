import 'package:flutter/material.dart';

import '../../models/menu_item.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/responsive.dart';
import '../../widgets/cart/cart_panel.dart';
import '../../widgets/header/app_header.dart';
import '../../widgets/menu/customization_dialog.dart';
import '../../widgets/menu/menu_item_card.dart';

class CustomerShellScreen extends StatefulWidget {
  const CustomerShellScreen({super.key});

  @override
  State<CustomerShellScreen> createState() => _CustomerShellScreenState();
}

class _CustomerShellScreenState extends State<CustomerShellScreen> {
  final _firebaseService = FirebaseService();
  String? _selectedCategory;

  List<String> _categoriesFrom(List<MenuItem> items) {
    return items.map((item) => item.category).toSet().toList()..sort();
  }

  Map<String, List<MenuItem>> _groupByCategory(List<MenuItem> items) {
    final grouped = <String, List<MenuItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveLayout.isDesktop(context);

    return Scaffold(
      backgroundColor: AppTheme.brandBackground,
      body: StreamBuilder<List<MenuItem>>(
        stream: _firebaseService.watchMenuItems(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Failed to load menu.\n${snapshot.error}'),
            );
          }

          final items = snapshot.data ?? [];
          final categories = _categoriesFrom(items);
          final filteredItems = _selectedCategory == null
              ? items
              : items.where((item) => item.category == _selectedCategory).toList();
          final groupedItems = _groupByCategory(filteredItems);

          return Column(
            children: [
              AppHeader(
                categories: categories,
                selectedCategory: _selectedCategory,
                onCategorySelected: (category) {
                  setState(() => _selectedCategory = category);
                },
              ),
              Expanded(
                child: isDesktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _MenuSections(groupedItems: groupedItems),
                          ),
                          const SideCartPanel(),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(
                            child: _MenuSections(groupedItems: groupedItems),
                          ),
                          const BottomCartBar(),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MenuSections extends StatelessWidget {
  const _MenuSections({required this.groupedItems});

  final Map<String, List<MenuItem>> groupedItems;

  @override
  Widget build(BuildContext context) {
    if (groupedItems.isEmpty) {
      return const Center(child: Text('No items in this category.'));
    }

    final isDesktop = ResponsiveLayout.isDesktop(context);
    final crossAxisCount = isDesktop ? 3 : 2;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: groupedItems.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.key,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.78,
                ),
                itemCount: entry.value.length,
                itemBuilder: (context, index) {
                  final item = entry.value[index];
                  return MenuItemCard(
                    item: item,
                    onTap: () => showCustomizationDialog(context, item),
                  );
                },
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
