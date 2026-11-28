import 'package:flutter/material.dart';

import '../../../services/inventory_api_service.dart';
import '../../../services/super_admin_scope_service.dart';
import 'inventory_theme.dart';
import 'inventory_transactions_pane.dart';
import 'inventory_reports_pane.dart';

/// Main inventory & costing hub — items, daily moves, reports (Foodics-style).
class InventoryModulePage extends StatefulWidget {
  const InventoryModulePage({super.key});

  @override
  State<InventoryModulePage> createState() => _InventoryModulePageState();
}

class _InventoryModulePageState extends State<InventoryModulePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  var _loading = true;
  String? _error;
  var _enabled = false;
  List<Map<String, dynamic>> _items = const [];
  List<Map<String, dynamic>> _levels = const [];

  String get _restaurantId => SuperAdminScopeService.instance.effectiveRestaurantId;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    SuperAdminScopeService.instance.addListener(_bootstrap);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    SuperAdminScopeService.instance.removeListener(_bootstrap);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final enabled = await InventoryApiService.instance.fetchEnabled(
        restaurantId: _restaurantId,
      );
      if (!enabled) {
        if (!mounted) return;
        setState(() {
          _enabled = false;
          _loading = false;
          _error = 'فعّل المخزون من إعدادات المطعم (inventoryEnabled) ثم أعد المحاولة.';
        });
        return;
      }
      final items = await InventoryApiService.instance.fetchItems(
        restaurantId: _restaurantId,
      );
      final levels = await InventoryApiService.instance.reportLevels(
        restaurantId: _restaurantId,
      );
      if (!mounted) return;
      setState(() {
        _enabled = true;
        _items = items;
        _levels = levels;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _addSampleRawItem() async {
    try {
      await InventoryApiService.instance.createItem(
        {
          'name': 'مادة خام جديدة',
          'itemType': 'RAW',
          'category': 'خام',
          'recipeUom': 'g',
          'storageUom': 'kg',
          'purchaseUom': 'كرتون',
          'storageToRecipeFactor': 1000,
        },
        restaurantId: _restaurantId,
      );
      await _bootstrap();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ColoredBox(
        color: InventoryTheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: InventoryTheme.burgundy,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            'المخزون والتكلفة',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: _bootstrap,
                            icon: const Icon(Icons.refresh, color: Colors.white),
                            tooltip: 'تحديث',
                          ),
                        ],
                      ),
                      TabBar(
                        controller: _tabs,
                        indicatorColor: InventoryTheme.accent,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white70,
                        tabs: const [
                          Tab(text: 'المواد والتحضيرات'),
                          Tab(text: 'الحركات اليومية'),
                          Tab(text: 'التقارير'),
                          Tab(text: 'مستويات المخزون'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: InventoryTheme.burgundy),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _bootstrap,
                style: FilledButton.styleFrom(backgroundColor: InventoryTheme.burgundy),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    if (!_enabled) {
      return Center(child: Text(_error ?? 'المخزون غير مفعّل'));
    }
    return TabBarView(
      controller: _tabs,
      children: [
        _itemsTab(),
        _transactionsTab(),
        _reportsTab(),
        _levelsTab(),
      ],
    );
  }

  Widget _itemsTab() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                FilledButton.icon(
                  onPressed: _addSampleRawItem,
                  style: FilledButton.styleFrom(
                    backgroundColor: InventoryTheme.accent,
                    foregroundColor: Colors.black87,
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('مادة خام'),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.separated(
            itemCount: _items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final row = _items[index];
              final type = row['itemType']?.toString() ?? 'RAW';
              final qty = row['currentQty'] ?? 0;
              final avg = row['avgCost'] ?? 0;
              return Card(
                child: ListTile(
                  title: Text(row['name']?.toString() ?? '—'),
                  subtitle: Text(
                    '$type • ${row['recipeUom'] ?? row['ingredientUom'] ?? 'وحدة'} • AVCO $avg',
                  ),
                  trailing: Text('$qty', style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _transactionsTab() {
    return InventoryTransactionsPane(
      restaurantId: _restaurantId,
      stockItems: _items,
      onRefresh: _bootstrap,
    );
  }

  Widget _reportsTab() {
    return InventoryReportsPane(restaurantId: _restaurantId);
  }

  Widget _levelsTab() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(InventoryTheme.burgundy),
        headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        columns: const [
          DataColumn(label: Text('الصنف')),
          DataColumn(label: Text('الكمية')),
          DataColumn(label: Text('AVCO')),
          DataColumn(label: Text('القيمة')),
          DataColumn(label: Text('الحالة')),
        ],
        rows: _levels.map((row) {
          return DataRow(
            cells: [
              DataCell(Text(row['name']?.toString() ?? '')),
              DataCell(Text('${row['currentQty'] ?? ''}')),
              DataCell(Text('${row['avgCost'] ?? ''}')),
              DataCell(Text('${row['totalValuation'] ?? ''}')),
              DataCell(InventoryStockBadge(code: row['stockStatus']?.toString() ?? 'OK')),
            ],
          );
        }).toList(),
      ),
    );
  }
}
