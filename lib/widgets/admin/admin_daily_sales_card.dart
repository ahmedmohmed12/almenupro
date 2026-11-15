import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/restaurant_settings.dart';
import '../../models/sales_platform_config.dart';
import '../../services/admin_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/restaurant_settings_service.dart';
import '../../services/super_admin_scope_service.dart';
import 'admin_responsive_layout.dart';
import 'settings/link_hub_qr_download.dart';

class AdminDailySalesCard extends StatefulWidget {
  const AdminDailySalesCard({super.key});

  @override
  State<AdminDailySalesCard> createState() => _AdminDailySalesCardState();
}

class _AdminDailySalesCardState extends State<AdminDailySalesCard> {
  static const burgundy = Color(0xFF6B1124);

  var _loading = true;
  var _exporting = false;
  var _days = 1;
  var _storeId = '';
  String? _error;
  Map<String, dynamic>? _data;
  List<SalesPlatformConfig> _platforms = SalesPlatformConfig.defaults();
  String? _loadedRestaurantId;

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

  void _onScopeChanged() {
    final nextId = _resolveRestaurantId();
    if (nextId != _loadedRestaurantId) {
      _load();
    }
  }

  String _resolveRestaurantId() {
    if (AdminAuthService.instance.isRestaurantAdmin) {
      return AdminAuthService.instance.restaurantId ??
          ApiService.defaultRestaurantId;
    }
    return SuperAdminScopeService.instance.effectiveRestaurantId;
  }

  bool get _canLoad {
    if (AdminAuthService.instance.isSuperAdmin) {
      return SuperAdminScopeService.instance.hasEffectiveRestaurant;
    }
    return _resolveRestaurantId().isNotEmpty;
  }

  Future<void> _load() async {
    if (!_canLoad) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _data = null;
        _loadedRestaurantId = null;
      });
      return;
    }

    final restaurantId = _resolveRestaurantId();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.instance.fetchDailySalesAnalytics(
          restaurantId: restaurantId,
          days: _days,
        ),
        RestaurantSettingsService.instance.load(restaurantId: restaurantId),
      ]);
      if (!mounted) return;
      setState(() {
        _data = results[0] as Map<String, dynamic>;
        _platforms = (results[1] as RestaurantSettings).resolvedSalesPlatforms;
        _loadedRestaurantId = restaurantId;
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

  SalesPlatformConfig _platformFromRow(Map<String, dynamic> row) =>
      PlatformCatalog.fromAnalyticsRow(row, _platforms);

  List<Map<String, dynamic>> get _storeRows =>
      (_data?['stores'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

  Map<String, dynamic>? get _selectedStore {
    if (_storeId.isEmpty) return null;
    for (final row in _storeRows) {
      if (row['storeId']?.toString() == _storeId) return row;
    }
    return null;
  }

  Future<void> _export(String format) async {
    if (_exporting || !_canLoad) return;
    setState(() => _exporting = true);
    try {
      final bytes = await ApiService.instance.fetchDailySalesExport(
        restaurantId: _resolveRestaurantId(),
        days: _days,
        storeId: _storeId,
        format: format,
      );
      if (format == 'csv') {
        await downloadBytesAsFile(
          Uint8List.fromList(bytes),
          filename: 'daily-sales.csv',
          mime: 'text/csv;charset=utf-8',
        );
      } else {
        await openReportPrintView(utf8.decode(bytes));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String? _emptyStateMessage() {
    final meta = _data?['meta'] as Map<String, dynamic>? ?? {};
    final dataState = meta['dataState']?.toString() ?? '';
    switch (dataState) {
      case 'zero_in_period':
        return 'لا توجد مبيعات في هذه الفترة — المطعم لديه طلبات سابقة.';
      case 'no_orders':
        return 'لا توجد طلبات مسجّلة لهذا المطعم بعد.';
      default:
        if ((_data?['summary']?['orders'] as num?)?.toInt() == 0) {
          return 'لا توجد مبيعات في هذه الفترة';
        }
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _selectedStore ??
        (_data?['summary'] as Map<String, dynamic>? ?? {});
    final stores = _storeRows;
    final storeIds = stores
        .map((row) => row['storeId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final selectedStoreId = storeIds.contains(_storeId) ? _storeId : '';

    final gross = (summary['grossRevenue'] as num?)?.toDouble() ?? 0;
    final net = (summary['netRevenue'] as num?)?.toDouble() ?? 0;
    final commission = (summary['commission'] as num?)?.toDouble() ?? 0;
    final orders = (summary['orders'] as num?)?.toInt() ?? 0;
    final average = (summary['averageOrderValue'] as num?)?.toDouble() ??
        (orders > 0 ? gross / orders : 0);
    final emptyMessage = _emptyStateMessage();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminSectionHeader(
              icon: Icons.storefront,
              title: 'تقرير المبيعات الموحّد',
              subtitle: 'التجميع حسب حساب المتجر، وليس حسب نوع المنصة',
              actions: [
                DropdownButton<String>(
                  value: selectedStoreId,
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('إجمالي كل المتاجر'),
                    ),
                    ...stores.map(
                      (row) => DropdownMenuItem(
                        value: row['storeId']?.toString() ?? '',
                        child: Text(row['storeName']?.toString() ?? ''),
                      ),
                    ),
                  ],
                  onChanged: _loading
                      ? null
                      : (value) => setState(() => _storeId = value ?? ''),
                ),
                DropdownButton<int>(
                  value: _days,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('اليوم')),
                    DropdownMenuItem(value: 7, child: Text('7 أيام')),
                    DropdownMenuItem(value: 30, child: Text('30 يوم')),
                  ],
                  onChanged: _loading
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _days = value);
                          _load();
                        },
                ),
                IconButton(
                  tooltip: 'تصدير CSV',
                  onPressed: _loading || _exporting ? null : () => _export('csv'),
                  icon: const Icon(Icons.table_view),
                ),
                IconButton(
                  tooltip: 'تصدير PDF',
                  onPressed: _loading || _exporting ? null : () => _export('pdf'),
                  icon: const Icon(Icons.picture_as_pdf),
                ),
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: burgundy),
                ),
              )
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red))
            else if (!_canLoad)
              const Text(
                'اختر مطعماً لعرض تقرير المبيعات.',
                style: TextStyle(color: Color(0xFF888888)),
              )
            else ...[
              AdminResponsiveGrid(
                minTileWidth: 160,
                children: [
                  _SummaryTile(
                    label: 'إجمالي المبيعات',
                    value: '${gross.toStringAsFixed(3)} د.ك',
                    icon: Icons.payments,
                    color: Colors.green,
                  ),
                  _SummaryTile(
                    label: 'صافي المطعم',
                    value: '${net.toStringAsFixed(3)} د.ك',
                    icon: Icons.account_balance_wallet,
                    color: burgundy,
                  ),
                  _SummaryTile(
                    label: 'عمولات المنصات',
                    value: '${commission.toStringAsFixed(3)} د.ك',
                    icon: Icons.percent,
                    color: Colors.orange,
                  ),
                  _SummaryTile(
                    label: 'عدد الطلبات',
                    value: '$orders',
                    icon: Icons.receipt_long,
                    color: Colors.blue,
                  ),
                  _SummaryTile(
                    label: 'متوسط الطلب',
                    value: '${average.toStringAsFixed(3)} د.ك',
                    icon: Icons.analytics,
                    color: const Color(0xFF0F766E),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'مقارنة المتاجر',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 10),
              if (stores.isEmpty && emptyMessage != null)
                Text(
                  emptyMessage,
                  style: const TextStyle(color: Color(0xFF888888)),
                )
              else if (stores.isEmpty)
                const Text(
                  'لا توجد مبيعات في هذه الفترة',
                  style: TextStyle(color: Color(0xFF888888)),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 40,
                    dataRowMinHeight: 42,
                    dataRowMaxHeight: 56,
                    columns: const [
                      DataColumn(label: Text('المتجر')),
                      DataColumn(label: Text('الطلبات')),
                      DataColumn(label: Text('إجمالي المبيعات')),
                      DataColumn(label: Text('متوسط الطلب')),
                      DataColumn(label: Text('الصافي')),
                    ],
                    rows: stores.map((row) {
                      final platform = _platformFromRow(row);
                      final rowGross =
                          (row['grossRevenue'] as num?)?.toDouble() ?? 0;
                      final rowNet = (row['netRevenue'] as num?)?.toDouble() ?? 0;
                      final rowOrders = (row['orders'] as num?)?.toInt() ?? 0;
                      final rowAverage =
                          (row['averageOrderValue'] as num?)?.toDouble() ?? 0;
                      final active = row['storeId']?.toString() == selectedStoreId;
                      return DataRow(
                        selected: active,
                        cells: [
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SalesPlatformBadge(platform: platform),
                                const SizedBox(width: 8),
                                Text(row['storeName']?.toString() ?? ''),
                              ],
                            ),
                          ),
                          DataCell(Text('$rowOrders')),
                          DataCell(Text('${rowGross.toStringAsFixed(3)} د.ك')),
                          DataCell(Text('${rowAverage.toStringAsFixed(3)} د.ك')),
                          DataCell(Text('${rowNet.toStringAsFixed(3)} د.ك')),
                        ],
                      );
                    }).toList(),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
