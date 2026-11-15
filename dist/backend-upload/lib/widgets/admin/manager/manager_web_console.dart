import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../../../models/manager_report_snapshot.dart';
import '../../../models/manager_report_period.dart';
import '../../../services/admin_auth_service.dart';
import '../admin_restaurant_selector.dart';
import 'manager_alert_list.dart';
import 'manager_chart_painters.dart';
import 'manager_period_chips.dart';

class ManagerWebConsole extends StatelessWidget {
  const ManagerWebConsole({
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${s.tr('لوحة المدير', 'Manager Dashboard')} — ${s.tr(snapshot.period.label, _periodLabel(snapshot.period))}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: burgundy,
                ),
              ),
            ),
            if (AdminAuthService.instance.isSuperAdmin)
              const Flexible(child: AdminRestaurantSelector()),
          ],
        ),
        const SizedBox(height: 10),
        ManagerPeriodChips(selected: period, onSelected: onPeriodChanged),
        const SizedBox(height: 10),
        ManagerAlertList(alerts: snapshot.alerts, onDismiss: onDismissAlert),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _metric(
              s.tr('صافي الإيراد', 'Net sales'),
              snapshot.netSales,
              s.currency,
              Icons.payments,
            ),
            _metric(
              s.tr('عدد الطلبات', 'Orders'),
              snapshot.orderCount.toDouble(),
              '',
              Icons.receipt_long,
              isInt: true,
            ),
            _metric(
              s.tr('متوسط التذكرة', 'Average ticket'),
              snapshot.avgTicket,
              s.currency,
              Icons.confirmation_number,
            ),
            _metric(
              s.tr('قيمة الملغى', 'Voided value'),
              snapshot.voidedAmount,
              s.currency,
              Icons.block,
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            final chart = _card(
              title: s.tr(snapshot.chartTitle, 'Sales over time'),
              child: ManagerAreaChart(
                values: snapshot.hourlySales,
                labels: snapshot.chartLabels,
                height: 190,
              ),
            );
            final donut = _card(
              title: s.tr('القنوات والدفع', 'Channels & Payment'),
              child: Column(
                children: [
                  ManagerDonutChart(
                    slices: snapshot.channels
                        .map(
                          (c) => (
                            label: c.label,
                            value: c.value,
                            color: Color(c.color),
                          ),
                        )
                        .toList(),
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${s.cash} ${snapshot.cashSales.toStringAsFixed(3)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '${s.knet} ${snapshot.knetSales.toStringAsFixed(3)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: chart),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: donut),
                ],
              );
            }
            return Column(children: [chart, const SizedBox(height: 12), donut]);
          },
        ),
        const SizedBox(height: 12),
        _card(
          title: s.tr('آخر الطلبات', 'Recent Orders'),
          child: snapshot.recentOrders.isEmpty
              ? Text(
                  s.tr(
                    'لا توجد طلبات في هذه الفترة.',
                    'No orders in this period.',
                  ),
                )
              : Column(
                  children: [
                    for (final order in snapshot.recentOrders)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${order.channel} · ${order.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              '${order.total.toStringAsFixed(3)} د.ك',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final table = _card(
              title: s.tr('أعلى 5 أصناف مبيعاً', 'Top 5 Selling Items'),
              child: snapshot.topItems.isEmpty
                  ? Text(
                      s.tr(
                        'لا توجد مبيعات في هذه الفترة.',
                        'No sales in this period.',
                      ),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < snapshot.topItems.length; i++)
                          _topRow(i + 1, snapshot.topItems[i]),
                      ],
                    ),
            );
            final shifts = _card(
              title: s.tr('الورديات والصندوق', 'Shifts & Cash Drawer'),
              child: snapshot.openShifts.isEmpty
                  ? Text(s.tr('لا توجد وردية مفتوحة.', 'No open shifts.'))
                  : Column(
                      children: [
                        for (final shift in snapshot.openShifts)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.point_of_sale,
                              color: burgundy,
                            ),
                            title: Text(shift.cashierName),
                            subtitle: Text(
                              '${s.tr('افتتاح', 'Opening')} ${shift.openingFloat.toStringAsFixed(3)} • '
                              '${s.tr('متوقع', 'Expected')} ${shift.summary.expectedCash.toStringAsFixed(3)} ${s.currency}',
                            ),
                            trailing: Text(
                              '${shift.summary.orderCount} ${s.tr('طلب', 'orders')}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: table),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: shifts),
                ],
              );
            }
            return Column(
              children: [table, const SizedBox(height: 12), shifts],
            );
          },
        ),
      ],
    );
  }

  String _periodLabel(ManagerReportPeriod period) => switch (period) {
    ManagerReportPeriod.live => 'Live',
    ManagerReportPeriod.lastHour => 'Last hour',
    ManagerReportPeriod.today => 'Today',
    ManagerReportPeriod.yesterday => 'Yesterday',
    ManagerReportPeriod.last7Days => 'Last 7 days',
    ManagerReportPeriod.last30Days => 'Last 30 days',
  };

  Widget _metric(
    String label,
    double value,
    String suffix,
    IconData icon, {
    bool isInt = false,
  }) {
    return SizedBox(
      width: 220,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: burgundy, size: 18),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            Text(
              isInt
                  ? value.toInt().toString()
                  : '${value.toStringAsFixed(3)}${suffix.isEmpty ? '' : ' $suffix'}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _topRow(int rank, ManagerTopItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: burgundy,
            child: Text(
              '$rank',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '×${item.quantity}',
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
          const SizedBox(width: 12),
          Text(
            '${item.revenue.toStringAsFixed(3)} د.ك',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
