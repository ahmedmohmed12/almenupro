import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/super_admin_scope_service.dart';
import '../../utils/food_cost_utils.dart';
import 'admin_breakpoints.dart';
import 'admin_responsive_layout.dart';

enum _FoodCostSortKey {
  revenue,
  quantity,
  foodCostPercent,
  grossProfit,
  name,
}

enum _MatrixFilter { all, star, plowhorse, puzzle, dog }

class AdminFoodCostReportPanel extends StatefulWidget {
  const AdminFoodCostReportPanel({super.key});

  @override
  State<AdminFoodCostReportPanel> createState() => _AdminFoodCostReportPanelState();
}

class _AdminFoodCostReportPanelState extends State<AdminFoodCostReportPanel> {
  static const burgundy = Color(0xFF6B1124);

  var _loading = true;
  var _days = 30;
  String? _error;
  Map<String, dynamic>? _data;
  _FoodCostSortKey _sortKey = _FoodCostSortKey.revenue;
  var _sortDesc = true;
  _MatrixFilter _matrixFilter = _MatrixFilter.all;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
    SuperAdminScopeService.instance.addListener(_onScopeChanged);
  }

  @override
  void dispose() {
    SuperAdminScopeService.instance.removeListener(_onScopeChanged);
    super.dispose();
  }

  void _onScopeChanged() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.instance.fetchFoodCostReport(
        restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
        days: _days,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _items {
    final raw = (_data?['items'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    Iterable<Map<String, dynamic>> filtered = raw;
    if (_matrixFilter != _MatrixFilter.all) {
      filtered = filtered.where(
        (row) => row['menuEngineeringCategory']?.toString() == _matrixFilter.name,
      );
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      filtered = filtered.where((row) {
        final name = row['name']?.toString().toLowerCase() ?? '';
        final sku = row['sku']?.toString().toLowerCase() ?? '';
        return name.contains(q) || sku.contains(q);
      });
    }

    final list = filtered.toList();
    list.sort((a, b) {
      int cmp;
      switch (_sortKey) {
        case _FoodCostSortKey.quantity:
          cmp = ((a['quantitySold'] as num?) ?? 0).compareTo(
            (b['quantitySold'] as num?) ?? 0,
          );
        case _FoodCostSortKey.foodCostPercent:
          cmp = ((a['foodCostPercent'] as num?) ?? -1).compareTo(
            (b['foodCostPercent'] as num?) ?? -1,
          );
        case _FoodCostSortKey.grossProfit:
          cmp = ((a['grossProfit'] as num?) ?? 0).compareTo(
            (b['grossProfit'] as num?) ?? 0,
          );
        case _FoodCostSortKey.name:
          cmp = (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? '');
        case _FoodCostSortKey.revenue:
          cmp = ((a['totalRevenue'] as num?) ?? 0).compareTo(
            (b['totalRevenue'] as num?) ?? 0,
          );
      }
      return _sortDesc ? -cmp : cmp;
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: burgundy));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }

    final summary = _data?['summary'] as Map<String, dynamic>? ?? {};
    final channels = (_data?['channels'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final matrix = _data?['matrix'] as Map<String, dynamic>? ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminSectionHeader(
          icon: Icons.pie_chart_outline,
          title: 'تقرير تكلفة الطعام وهندسة المنيو',
          subtitle:
              'إيرادات + فود كوست + مصفوفة Stars / Plowhorses / Puzzles / Dogs',
          actions: [
            DropdownButton<int>(
              value: _days,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 7, child: Text('7 أيام')),
                DropdownMenuItem(value: 30, child: Text('30 يوم')),
                DropdownMenuItem(value: 90, child: Text('90 يوم')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _days = value);
                _load();
              },
            ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildKpiRow(summary),
        const SizedBox(height: 16),
        _buildChannelBreakdown(channels),
        const SizedBox(height: 16),
        _buildMatrixSummary(matrix),
        const SizedBox(height: 16),
        _buildTableControls(),
        const SizedBox(height: 8),
        _buildItemsTable(),
      ],
    );
  }

  Widget _buildKpiRow(Map<String, dynamic> summary) {
    return AdminResponsiveGrid(
      minTileWidth: 180,
      children: [
        _KpiCard(
          label: 'الإيرادات الإجمالية',
          value: _fmt(summary['totalRevenue']),
          icon: Icons.payments_outlined,
          color: const Color(0xFF1565C0),
        ),
        _KpiCard(
          label: 'إجمالي تكلفة الطعام',
          value: _fmt(summary['totalFoodCost']),
          icon: Icons.restaurant,
          color: const Color(0xFFC62828),
        ),
        _KpiCard(
          label: 'مجمل الربح %',
          value: _fmtPercent(summary['grossProfitMarginPercent']),
          icon: Icons.trending_up,
          color: const Color(0xFF2E7D32),
        ),
        _KpiCard(
          label: 'نسبة الفود كوست %',
          value: _fmtPercent(summary['overallFoodCostPercent']),
          icon: Icons.percent,
          color: burgundy,
        ),
      ],
    );
  }

  Widget _buildChannelBreakdown(List<Map<String, dynamic>> channels) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'تفصيل قنوات المبيعات',
              style: TextStyle(fontWeight: FontWeight.bold, color: burgundy),
            ),
            const SizedBox(height: 12),
            AdminResponsiveGrid(
              minTileWidth: 220,
              children: channels.map(_channelCard).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _channelCard(Map<String, dynamic> row) {
    final label = row['labelAr']?.toString() ?? row['channel']?.toString() ?? '';
    final revenue = (row['totalRevenue'] as num?)?.toDouble() ?? 0;
    final foodCost = (row['totalFoodCost'] as num?)?.toDouble() ?? 0;
    final foodPct = (row['foodCostPercent'] as num?)?.toDouble();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('الكمية: ${row['quantitySold'] ?? 0}'),
          Text('الإيراد: ${_fmt(row['totalRevenue'])}'),
          Text('الفود كوست: ${_fmt(row['totalFoodCost'])}'),
          if (foodPct != null && revenue > 0) ...[
            const SizedBox(height: 6),
            FoodCostBadge(
              sellingPrice: revenue,
              costPrice: foodCost,
              compact: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMatrixSummary(Map<String, dynamic> matrix) {
    final entries = [
      ('star', const Color(0xFF2E7D32), Icons.star),
      ('plowhorse', const Color(0xFF1565C0), Icons.agriculture),
      ('puzzle', const Color(0xFFF9A825), Icons.extension),
      ('dog', const Color(0xFFC62828), Icons.pets),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'مصفوفة هندسة المنيو',
              style: TextStyle(fontWeight: FontWeight.bold, color: burgundy),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: entries.map((entry) {
                final block = matrix[entry.$1] as Map<String, dynamic>? ?? {};
                final count = (block['count'] as num?)?.toInt() ?? 0;
                final label = block['labelAr']?.toString() ?? entry.$1;
                final selected = _matrixFilter.name == entry.$1;
                return FilterChip(
                  selected: selected,
                  label: Text('$label ($count)'),
                  avatar: Icon(entry.$3, size: 16, color: entry.$2),
                  onSelected: (_) {
                    setState(() {
                      _matrixFilter = selected
                          ? _MatrixFilter.all
                          : _MatrixFilter.values.firstWhere(
                              (f) => f.name == entry.$1,
                              orElse: () => _MatrixFilter.all,
                            );
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableControls() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 160, maxWidth: 280),
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              labelText: 'بحث بالاسم / SKU',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        DropdownButton<_FoodCostSortKey>(
          value: _sortKey,
          isExpanded: false,
          items: const [
            DropdownMenuItem(
              value: _FoodCostSortKey.revenue,
              child: Text('ترتيب: الإيراد'),
            ),
            DropdownMenuItem(
              value: _FoodCostSortKey.quantity,
              child: Text('ترتيب: الكمية'),
            ),
            DropdownMenuItem(
              value: _FoodCostSortKey.foodCostPercent,
              child: Text('ترتيب: % الفود كوست'),
            ),
            DropdownMenuItem(
              value: _FoodCostSortKey.grossProfit,
              child: Text('ترتيب: الربح'),
            ),
            DropdownMenuItem(
              value: _FoodCostSortKey.name,
              child: Text('ترتيب: الاسم'),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _sortKey = value);
          },
        ),
        IconButton(
          tooltip: _sortDesc ? 'تنازلي' : 'تصاعدي',
          onPressed: () => setState(() => _sortDesc = !_sortDesc),
          icon: Icon(_sortDesc ? Icons.arrow_downward : Icons.arrow_upward),
        ),
      ],
    );
  }

  Widget _buildItemsTable() {
    final items = _items;
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('لا توجد بيانات مبيعات في الفترة المحددة')),
      );
    }

    return AdminScrollableTable(
      minTableWidth: 1020,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(
          burgundy.withValues(alpha: 0.06),
        ),
        columnSpacing: 16,
        columns: const [
          DataColumn(label: Text('SKU')),
          DataColumn(label: Text('الصنف')),
          DataColumn(label: Text('الفئة')),
          DataColumn(label: Text('الكمية')),
          DataColumn(label: Text('تكلفة / بيع')),
          DataColumn(label: Text('الإيراد')),
          DataColumn(label: Text('فود كوست')),
          DataColumn(label: Text('% FC')),
          DataColumn(label: Text('صافي الربح')),
          DataColumn(label: Text('المصفوفة')),
        ],
        rows: items.map((row) {
          final selling = (row['sellingPrice'] as num?)?.toDouble() ?? 0;
          final cost = (row['costPrice'] as num?)?.toDouble();
          final revenue = (row['totalRevenue'] as num?)?.toDouble() ?? 0;
          final foodCostTotal = (row['totalFoodCost'] as num?)?.toDouble() ?? 0;
          final matrixLabel = row['menuEngineeringLabelAr']?.toString() ?? '';

          return DataRow(
            cells: [
              DataCell(Text(row['sku']?.toString() ?? '')),
              DataCell(
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    row['name']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(Text(row['categoryName']?.toString() ?? '')),
              DataCell(Text('${row['quantitySold'] ?? 0}')),
              DataCell(
                Text(
                  cost != null
                      ? '${cost.toStringAsFixed(3)} / ${selling.toStringAsFixed(3)}'
                      : '— / ${selling.toStringAsFixed(3)}',
                ),
              ),
              DataCell(Text(_fmt(row['totalRevenue']))),
              DataCell(Text(_fmt(row['totalFoodCost']))),
              DataCell(
                cost != null && revenue > 0
                    ? FoodCostBadge(
                        sellingPrice: revenue,
                        costPrice: foodCostTotal,
                        compact: true,
                      )
                    : const Text('—'),
              ),
              DataCell(Text(_fmt(row['netProfit']))),
              DataCell(_matrixBadge(matrixLabel, row['menuEngineeringCategory']?.toString())),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _matrixBadge(String label, String? key) {
    Color color;
    switch (key) {
      case 'star':
        color = const Color(0xFF2E7D32);
      case 'plowhorse':
        color = const Color(0xFF1565C0);
      case 'puzzle':
        color = const Color(0xFFF9A825);
      default:
        color = const Color(0xFFC62828);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  String _fmt(dynamic value) {
    final n = (value as num?)?.toDouble() ?? 0;
    return '${n.toStringAsFixed(3)} د.ك';
  }

  String _fmtPercent(dynamic value) {
    final n = (value as num?)?.toDouble() ?? 0;
    return '${n.toStringAsFixed(1)}%';
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 10),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
