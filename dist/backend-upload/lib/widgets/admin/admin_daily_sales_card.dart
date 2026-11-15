import 'package:flutter/material.dart';

import '../../models/restaurant_settings.dart';
import '../../models/sales_platform_config.dart';
import '../../services/admin_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/restaurant_settings_service.dart';
import '../../services/super_admin_scope_service.dart';
import 'admin_responsive_layout.dart';

class AdminDailySalesCard extends StatefulWidget {
  const AdminDailySalesCard({super.key});

  @override
  State<AdminDailySalesCard> createState() => _AdminDailySalesCardState();
}

class _AdminDailySalesCardState extends State<AdminDailySalesCard> {
  static const burgundy = Color(0xFF6B1124);

  var _loading = true;
  var _days = 1;
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
    final summary = _data?['summary'] as Map<String, dynamic>? ?? {};
    final platforms = (_data?['platforms'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    final gross = (summary['grossRevenue'] as num?)?.toDouble() ?? 0;
    final net = (summary['netRevenue'] as num?)?.toDouble() ?? 0;
    final commission = (summary['commission'] as num?)?.toDouble() ?? 0;
    final orders = (summary['orders'] as num?)?.toInt() ?? 0;
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
              subtitle: 'تفصيل ديناميكي حسب قناة البيع — أي منصة جديدة تظهر تلقائياً',
              actions: [
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
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'حسب قناة البيع',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 10),
              if (platforms.isEmpty && emptyMessage != null)
                Text(
                  emptyMessage,
                  style: const TextStyle(color: Color(0xFF888888)),
                )
              else if (platforms.isEmpty)
                const Text(
                  'لا توجد مبيعات في هذه الفترة',
                  style: TextStyle(color: Color(0xFF888888)),
                )
              else
                ...platforms.map((row) {
                  final platform = _platformFromRow(row);
                  final rowGross =
                      (row['grossRevenue'] as num?)?.toDouble() ?? 0;
                  final rowNet = (row['netRevenue'] as num?)?.toDouble() ?? 0;
                  final rowOrders = (row['orders'] as num?)?.toInt() ?? 0;
                  final share = (row['sharePercent'] as num?)?.toDouble() ?? 0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: platform.color.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: platform.color.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        SalesPlatformBadge(platform: platform),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$rowOrders طلب • ${share.toStringAsFixed(1)}% من الإجمالي',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF666666),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'إجمالي ${rowGross.toStringAsFixed(3)} — صافي ${rowNet.toStringAsFixed(3)} د.ك',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
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
