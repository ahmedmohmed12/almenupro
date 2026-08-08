import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/super_admin_scope_service.dart';

class AdminSmartUpsellAnalyticsCard extends StatefulWidget {
  const AdminSmartUpsellAnalyticsCard({super.key});

  @override
  State<AdminSmartUpsellAnalyticsCard> createState() =>
      _AdminSmartUpsellAnalyticsCardState();
}

class _AdminSmartUpsellAnalyticsCardState
    extends State<AdminSmartUpsellAnalyticsCard> {
  static const burgundy = Color(0xFF6B1124);
  static const gold = Color(0xFFD49A00);

  var _loading = true;
  var _days = 30;
  String? _error;
  Map<String, dynamic>? _data;

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
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.instance.fetchUpsellAnalytics(
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
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: burgundy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.insights, color: burgundy),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تقارير البياع الشاطر — المرحلة 3',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: burgundy,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'معدل القبول، الإيرادات الإضافية، ورفع متوسط قيمة الطلب.',
                        style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
                      ),
                    ],
                  ),
                ),
                DropdownButton<int>(
                  value: _days,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 7, child: Text('7 أيام')),
                    DropdownMenuItem(value: 30, child: Text('30 يوم')),
                    DropdownMenuItem(value: 90, child: Text('90 يوم')),
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
            const SizedBox(height: 20),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(color: burgundy),
                ),
              )
            else if (_error != null)
              _ErrorState(message: _error!, onRetry: _load)
            else
              _AnalyticsBody(data: _data ?? const {}),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  const _AnalyticsBody({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final summary = Map<String, dynamic>.from(data['summary'] as Map? ?? {});
    final topItems = (data['topItems'] as List?)
            ?.map((row) => Map<String, dynamic>.from(row as Map))
            .toList() ??
        const [];
    final surfaces = (data['surfaces'] as List?)
            ?.map((row) => Map<String, dynamic>.from(row as Map))
            .toList() ??
        const [];

    final impressions = summary['impressions'] as int? ?? 0;
    final conversions = summary['conversions'] as int? ?? 0;
    final conversionRate = (summary['conversionRate'] as num?)?.toDouble() ?? 0;
    final revenue = (summary['revenue'] as num?)?.toDouble() ?? 0;
    final aovLift = (summary['aovLiftPercent'] as num?)?.toDouble() ?? 0;
    final avgWith = (summary['avgAovWithUpsell'] as num?)?.toDouble() ?? 0;
    final avgWithout = (summary['avgAovWithoutUpsell'] as num?)?.toDouble() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final crossCount = constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 560
                    ? 2
                    : 1;
            return GridView.count(
              crossAxisCount: crossCount,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: crossCount == 1 ? 2.6 : 1.8,
              children: [
                _MetricTile(
                  label: 'مرات الظهور',
                  value: '$impressions',
                  icon: Icons.visibility_outlined,
                  color: const Color(0xFF1565C0),
                ),
                _MetricTile(
                  label: 'مرات القبول',
                  value: '$conversions',
                  icon: Icons.add_shopping_cart_outlined,
                  color: const Color(0xFF2E7D32),
                ),
                _MetricTile(
                  label: 'معدل التحويل',
                  value: '${conversionRate.toStringAsFixed(1)}%',
                  icon: Icons.percent,
                  color: _AdminSmartUpsellAnalyticsCardState.burgundy,
                ),
                _MetricTile(
                  label: 'إيراد Upsell',
                  value: '${revenue.toStringAsFixed(3)} د.ك',
                  icon: Icons.payments_outlined,
                  color: _AdminSmartUpsellAnalyticsCardState.gold,
                ),
                _MetricTile(
                  label: 'متوسط الطلب (مع Upsell)',
                  value: '${avgWith.toStringAsFixed(3)} د.ك',
                  icon: Icons.trending_up,
                  color: const Color(0xFF6A1B9A),
                ),
                _MetricTile(
                  label: 'رفع AOV',
                  value: '${aovLift >= 0 ? '+' : ''}${aovLift.toStringAsFixed(1)}%',
                  subtitle: 'بدون Upsell: ${avgWithout.toStringAsFixed(3)} د.ك',
                  icon: Icons.auto_graph,
                  color: aovLift >= 0 ? const Color(0xFF00838F) : Colors.red.shade700,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        if (topItems.isEmpty)
          const _EmptyHint(
            message:
                'لا توجد بيانات Upsell بعد. ستظهر الإحصائيات بعد ظهور الاقتراحات للزبائن وقبولهم.',
          )
        else ...[
          const Text(
            'أفضل الأصناف والإضافات',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: _AdminSmartUpsellAnalyticsCardState.burgundy,
            ),
          ),
          const SizedBox(height: 10),
          _TopItemsTable(items: topItems),
        ],
        if (surfaces.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text(
            'حسب مصدر الاقتراح',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: _AdminSmartUpsellAnalyticsCardState.burgundy,
            ),
          ),
          const SizedBox(height: 10),
          ...surfaces.map((row) => _SurfaceRow(row: row)),
        ],
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF666666),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
            ),
          ],
        ],
      ),
    );
  }
}

class _TopItemsTable extends StatelessWidget {
  const _TopItemsTable({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(
          _AdminSmartUpsellAnalyticsCardState.burgundy.withValues(alpha: 0.06),
        ),
        columns: const [
          DataColumn(label: Text('الصنف')),
          DataColumn(label: Text('ظهور')),
          DataColumn(label: Text('قبول')),
          DataColumn(label: Text('تحويل %')),
          DataColumn(label: Text('إيراد')),
        ],
        rows: items.map((row) {
          final name = row['itemName']?.toString() ?? '—';
          final impressions = row['impressions'] as int? ?? 0;
          final conversions = row['conversions'] as int? ?? 0;
          final rate = (row['conversionRate'] as num?)?.toDouble() ?? 0;
          final revenue = (row['revenue'] as num?)?.toDouble() ?? 0;
          return DataRow(
            cells: [
              DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
              DataCell(Text('$impressions')),
              DataCell(Text('$conversions')),
              DataCell(Text('${rate.toStringAsFixed(1)}%')),
              DataCell(Text('${revenue.toStringAsFixed(3)} د.ك')),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _SurfaceRow extends StatelessWidget {
  const _SurfaceRow({required this.row});

  final Map<String, dynamic> row;

  String _surfaceLabel(String raw) {
    switch (raw) {
      case 'smart_recommendations':
        return 'اقتراحات ذكية';
      case 'impulse_bumps':
        return 'إضافات سريعة';
      case 'linked_sides':
        return 'سايد إيتمز مربوطة';
      case 'free_delivery':
        return 'شريط التوصيل المجاني';
      default:
        return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = row['surface']?.toString() ?? 'unknown';
    final impressions = row['impressions'] as int? ?? 0;
    final conversions = row['conversions'] as int? ?? 0;
    final rate = (row['conversionRate'] as num?)?.toDouble() ?? 0;
    final revenue = (row['revenue'] as num?)?.toDouble() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _surfaceLabel(surface),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text('$impressions ظهور'),
          const SizedBox(width: 12),
          Text('$conversions قبول'),
          const SizedBox(width: 12),
          Text('${rate.toStringAsFixed(1)}%'),
          const SizedBox(width: 12),
          Text(
            '${revenue.toStringAsFixed(3)} د.ك',
            style: const TextStyle(
              color: _AdminSmartUpsellAnalyticsCardState.gold,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF888888)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF666666), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(message, style: TextStyle(color: Colors.red.shade700)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('إعادة المحاولة'),
        ),
      ],
    );
  }
}
