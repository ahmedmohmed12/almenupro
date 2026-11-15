import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../../../models/manager_report_snapshot.dart';
import '../../../models/manager_report_period.dart';
import '../../../models/restaurant.dart';
import '../../../services/admin_auth_service.dart';
import '../../../services/super_admin_scope_service.dart';
import 'manager_alert_list.dart';
import 'manager_period_chips.dart';

class ManagerOwnerMobileView extends StatelessWidget {
  const ManagerOwnerMobileView({
    super.key,
    required this.snapshot,
    required this.period,
    required this.onPeriodChanged,
    required this.onDismissAlert,
  });

  final ManagerReportSnapshot snapshot;
  final ManagerReportPeriod period;
  final ValueChanged<ManagerReportPeriod> onPeriodChanged;
  final ValueChanged<String> onDismissAlert;

  static const burgundy = Color(0xFF6B1124);

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final delta = snapshot.weekDeltaPercent;
    final up = delta >= 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        _BranchSwitch(),
        const SizedBox(height: 10),
        ManagerPeriodChips(selected: period, onSelected: onPeriodChanged),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6B1124), Color(0xFF3F0A16)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _LivePulse(active: snapshot.live),
                  const SizedBox(width: 8),
                  Text(
                    snapshot.salesTitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${snapshot.netSales.toStringAsFixed(3)} ${s.currency}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${up ? '+' : ''}${delta.toStringAsFixed(0)}% ${snapshot.comparisonLabel}',
                style: TextStyle(
                  color: up ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _pill(s.cash, snapshot.cashSales, const Color(0xFF059669)),
            _pill(s.knet, snapshot.knetSales, const Color(0xFF2563EB)),
            _countPill(s.tr('طلبات', 'Orders'), snapshot.orderCount),
          ],
        ),
        const SizedBox(height: 12),
        ManagerAlertList(alerts: snapshot.alerts, onDismiss: onDismissAlert),
        if (snapshot.recentOrders.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            s.tr('آخر الطلبات', 'Recent Orders'),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: burgundy,
            ),
          ),
          const SizedBox(height: 8),
          for (final order in snapshot.recentOrders)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${order.channel} · ${order.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${order.total.toStringAsFixed(3)} ${s.currency}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _pill(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label  ${value.toStringAsFixed(3)}',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _countPill(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: burgundy.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label  $value',
        style: const TextStyle(
          color: burgundy,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _LivePulse extends StatefulWidget {
  const _LivePulse({required this.active});

  final bool active;

  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = widget.active ? _c.value : 0.0;
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: Color.lerp(const Color(0xFF22C55E), Colors.white, t * 0.45),
            shape: BoxShape.circle,
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.7),
                      blurRadius: 8 + t * 6,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}

class _BranchSwitch extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final auth = AdminAuthService.instance;
    if (!auth.isSuperAdmin) {
      return Text(
        auth.restaurantName ?? s.tr('فرعك', 'Your branch'),
        style: const TextStyle(fontWeight: FontWeight.w700),
      );
    }
    return AnimatedBuilder(
      animation: SuperAdminScopeService.instance,
      builder: (context, _) {
        final scope = SuperAdminScopeService.instance;
        final restaurants = scope.restaurants;
        if (restaurants.isEmpty) {
          return OutlinedButton(
            onPressed: scope.refreshRestaurants,
            child: Text(s.tr('تحميل الفروع', 'Load branches')),
          );
        }
        return DropdownButtonFormField<String>(
          value: scope.selectedRestaurantId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: s.tr('الفرع', 'Branch'),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          items: restaurants
              .map(
                (Restaurant r) => DropdownMenuItem(
                  value: r.id,
                  child: Text(r.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (id) {
            if (id == null) return;
            final match = restaurants.firstWhere((r) => r.id == id);
            scope.selectRestaurant(match);
          },
        );
      },
    );
  }
}
