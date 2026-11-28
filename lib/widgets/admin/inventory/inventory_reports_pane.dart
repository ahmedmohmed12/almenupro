import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/inventory_api_service.dart';
import 'inventory_report_export.dart';
import 'inventory_theme.dart';

class InventoryReportsPane extends StatefulWidget {
  const InventoryReportsPane({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  State<InventoryReportsPane> createState() => _InventoryReportsPaneState();
}

class _InventoryReportsPaneState extends State<InventoryReportsPane> {
  var _loading = false;
  DateTimeRange? _range;
  final _categoryCtrl = TextEditingController();

  List<Map<String, dynamic>> _levels = const [];
  List<Map<String, dynamic>> _cogs = const [];
  List<Map<String, dynamic>> _variance = const [];
  List<Map<String, dynamic>> _history = const [];
  Map<String, dynamic> _purchasingWaste = const {};

  String? get _from => _range != null ? _range!.start.toIso8601String() : null;
  String? get _to => _range != null ? _range!.end.toIso8601String() : null;
  String? get _category =>
      _categoryCtrl.text.trim().isEmpty ? null : _categoryCtrl.text.trim();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: now.subtract(const Duration(days: 30)),
      end: now,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _categoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
      helpText: 'فترة التقرير',
    );
    if (picked != null) {
      setState(() => _range = picked);
      await _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rid = widget.restaurantId;
      final results = await Future.wait([
        InventoryApiService.instance.reportLevels(restaurantId: rid, category: _category),
        InventoryApiService.instance.reportCogs(
          restaurantId: rid,
          from: _from,
          to: _to,
          category: _category,
        ),
        InventoryApiService.instance.reportVariance(
          restaurantId: rid,
          from: _from,
          to: _to,
          category: _category,
        ),
        InventoryApiService.instance.reportHistory(
          restaurantId: rid,
          from: _from,
          to: _to,
        ),
        InventoryApiService.instance.reportPurchasingWaste(
          restaurantId: rid,
          from: _from,
          to: _to,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _levels = results[0] as List<Map<String, dynamic>>;
        _cogs = results[1] as List<Map<String, dynamic>>;
        _variance = results[2] as List<Map<String, dynamic>>;
        _history = results[3] as List<Map<String, dynamic>>;
        _purchasingWaste = Map<String, dynamic>.from(results[4] as Map);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  String _rangeLabel() {
    if (_range == null) return 'كل الفترات';
    final fmt = DateFormat.yMMMd('ar');
    return '${fmt.format(_range!.start)} — ${fmt.format(_range!.end)}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickRange,
                        icon: const Icon(Icons.date_range),
                        label: Text(_rangeLabel()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
                  ],
                ),
                TextField(
                  controller: _categoryCtrl,
                  decoration: InputDecoration(
                    labelText: 'تصفية حسب التصنيف',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _load,
                    ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ],
            ),
          ),
        ),
        if (_loading)
          const Expanded(
            child: Center(child: CircularProgressIndicator(color: InventoryTheme.burgundy)),
          )
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section(
                  title: 'تكلفة الأصناف (COGS)',
                  rows: _cogs,
                  columns: const [
                    'menuItemId',
                    'name',
                    'soldQty',
                    'netSales',
                    'unitCost',
                    'totalCogs',
                    'profit',
                    'foodCostPct',
                  ],
                ),
                _section(
                  title: 'انحراف المخزون',
                  rows: _variance,
                  columns: const [
                    'itemId',
                    'name',
                    'actualConsumption',
                    'theoreticalConsumption',
                    'varianceQty',
                    'varianceCost',
                  ],
                ),
                _section(
                  title: 'مستويات المخزون',
                  rows: _levels,
                  columns: const [
                    'itemId',
                    'name',
                    'currentQty',
                    'avgCost',
                    'totalValuation',
                    'stockStatus',
                  ],
                ),
                _section(
                  title: 'سجل الحركات',
                  rows: _history,
                  columns: const [
                    'date',
                    'type',
                    'referenceId',
                    'inQty',
                    'outQty',
                    'runningBalance',
                    'unitCost',
                  ],
                ),
                _purchasingWasteSection(),
              ],
            ),
          ),
      ],
    );
  }

  Widget _purchasingWasteSection() {
    final purchases = _purchasingWaste['purchasesBySupplier'];
    final waste = _purchasingWaste['wasteByReason'];
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('المشتريات والهالك', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final purchaseRows = purchases is List
                        ? purchases.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
                        : <Map<String, dynamic>>[];
                    final wasteRows = waste is List
                        ? waste.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
                        : <Map<String, dynamic>>[];
                    final csv = StringBuffer()
                      ..writeln('--- purchases ---')
                      ..writeln(InventoryReportExport.toCsv(purchaseRows, const ['supplier', 'total']))
                      ..writeln('--- waste ---')
                      ..writeln(InventoryReportExport.toCsv(wasteRows, const ['reason', 'qty']));
                    await InventoryReportExport.copyToClipboard(context, csv.toString(), 'المشتريات والهالك');
                  },
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('تصدير CSV'),
                ),
              ],
            ),
            if (purchases is List)
              ...purchases.take(8).map(
                    (p) => ListTile(
                      dense: true,
                      title: Text('${p['supplier']}'),
                      trailing: Text('${p['total']}'),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    required List<Map<String, dynamic>> rows,
    required List<String> columns,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                TextButton.icon(
                  onPressed: rows.isEmpty
                      ? null
                      : () => InventoryReportExport.copyToClipboard(
                            context,
                            InventoryReportExport.toCsv(rows, columns),
                            title,
                          ),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('تصدير CSV'),
                ),
              ],
            ),
            if (rows.isEmpty) const Text('لا بيانات في الفترة المحددة.'),
            ...rows.take(12).map(
                  (r) => ListTile(
                    dense: true,
                    title: Text(r['name']?.toString() ?? r['menuItemId']?.toString() ?? '—'),
                    subtitle: Text(columns.skip(1).take(3).map((c) => '$c: ${r[c]}').join(' • ')),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}