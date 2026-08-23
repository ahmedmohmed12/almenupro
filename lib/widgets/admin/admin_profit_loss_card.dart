import 'package:flutter/material.dart';

import '../../models/expense.dart';
import '../../services/admin_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/super_admin_scope_service.dart';
import '../../theme/app_theme.dart';

class AdminProfitLossCard extends StatefulWidget {
  const AdminProfitLossCard({super.key});

  @override
  State<AdminProfitLossCard> createState() => _AdminProfitLossCardState();
}

class _AdminProfitLossCardState extends State<AdminProfitLossCard> {
  static const burgundy = Color(0xFF6B1124);
  var _days = 30;
  var _loading = true;
  String? _error;
  PnlReport _report = const PnlReport();

  @override
  void initState() {
    super.initState();
    SuperAdminScopeService.instance.addListener(_onScopeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    SuperAdminScopeService.instance.removeListener(_onScopeChanged);
    super.dispose();
  }

  void _onScopeChanged() => _load();

  String get _restaurantId {
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
    return _restaurantId.isNotEmpty;
  }

  Future<void> _load() async {
    if (!_canLoad) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _report = const PnlReport();
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await ApiService.instance.fetchPnlReport(
        restaurantId: _restaurantId,
        days: _days,
      );
      if (!mounted) return;
      setState(() {
        _report = report;
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

  String get _healthLabel {
    switch (_report.health) {
      case 'profit':
        return 'ربحية إيجابية';
      case 'loss':
        return 'خسارة صافية';
      case 'breakeven':
        return 'نقطة تعادل';
      default:
        return 'لا توجد بيانات كافية';
    }
  }

  Color get _healthColor {
    switch (_report.health) {
      case 'profit':
        return const Color(0xFF1B7A4A);
      case 'loss':
        return const Color(0xFFB3261E);
      case 'breakeven':
        return AppTheme.brandOrange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: burgundy.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'الأرباح والخسائر (Net P&L)',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: burgundy,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _PeriodChip(
                label: 'يومي',
                selected: _days == 1,
                onTap: () {
                  setState(() => _days = 1);
                  _load();
                },
              ),
              _PeriodChip(
                label: 'أسبوعي',
                selected: _days == 7,
                onTap: () {
                  setState(() => _days = 7);
                  _load();
                },
              ),
              _PeriodChip(
                label: 'شهري',
                selected: _days == 30,
                onTap: () {
                  setState(() => _days = 30);
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.brandOrange),
              ),
            )
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red))
          else ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _KpiTile(
                  label: 'إجمالي الإيراد',
                  value: _report.netRevenue,
                  color: burgundy,
                ),
                _KpiTile(
                  label: 'إجمالي المصاريف',
                  value: _report.totalExpenses,
                  color: AppTheme.brandOrange,
                ),
                _KpiTile(
                  label: 'صافي الربح',
                  value: _report.netProfit,
                  color: _healthColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '$_healthLabel · هامش ${_report.marginPercent.toStringAsFixed(1)}% · نسبة المصروف ${_report.expenseRatio.toStringAsFixed(1)}%',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _healthColor,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'الإيراد مقابل المصروف',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            _TrendBars(series: _report.series),
            const SizedBox(height: 16),
            const Text(
              'توزيع المصاريف حسب التصنيف',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (_report.categories.isEmpty)
              const Text('لا توجد مصاريف مسجّلة في هذه الفترة.')
            else
              ..._report.categories.map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 88,
                        child: Text(expenseCategoryLabel(row.category)),
                      ),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: (row.sharePercent / 100).clamp(0, 1),
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(8),
                          color: AppTheme.brandOrange,
                          backgroundColor: const Color(0xFFFFE8CC),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${row.amount.toStringAsFixed(3)} د.ك'),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: const Color(0xFF6B1124),
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFF6B1124),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            '${value.toStringAsFixed(3)} د.ك',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendBars extends StatelessWidget {
  const _TrendBars({required this.series});

  final List<PnlDayPoint> series;

  @override
  Widget build(BuildContext context) {
    final visible = series.where((p) => p.revenue > 0 || p.expenses > 0).toList();
    final points = visible.isEmpty ? series.take(7).toList() : visible;
    final maxVal = points.fold<double>(0, (m, p) {
      final peak = p.revenue > p.expenses ? p.revenue : p.expenses;
      return peak > m ? peak : m;
    });
    if (points.isEmpty || maxVal <= 0) {
      return const Text('لا توجد حركة مالية كافية لعرض الرسم.');
    }
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: points.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final point = points[index];
          return SizedBox(
            width: 36,
            child: Column(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Container(
                            height: 100 * (point.revenue / maxVal),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6B1124),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Container(
                            height: 100 * (point.expenses / maxVal),
                            decoration: BoxDecoration(
                              color: AppTheme.brandOrange,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  point.date.length >= 10 ? point.date.substring(5) : point.date,
                  style: const TextStyle(fontSize: 9),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
