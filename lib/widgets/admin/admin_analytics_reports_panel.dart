import 'package:flutter/material.dart';

import '../../services/admin_auth_service.dart';
import '../../services/super_admin_scope_service.dart';
import 'admin_daily_sales_card.dart';
import 'admin_food_cost_report_panel.dart';
import 'admin_profit_loss_card.dart';
import 'admin_shift_reports_card.dart';
import 'hr/hr_summary_card.dart';
import 'manager/admin_manager_reports_panel.dart';

class AdminAnalyticsReportsPanel extends StatelessWidget {
  const AdminAnalyticsReportsPanel({super.key, this.onOpenHr});

  static const burgundy = Color(0xFF6B1124);
  final VoidCallback? onOpenHr;

  @override
  Widget build(BuildContext context) {
    final scope = SuperAdminScopeService.instance;
    final isSuperAdmin = AdminAuthService.instance.isSuperAdmin;
    final needsSelection = isSuperAdmin && !scope.hasEffectiveRestaurant;

    if (needsSelection) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'اختر مطعماً من قائمة المطاعم في الشريط الجانبي لعرض التقارير.',
          style: TextStyle(color: Colors.orange),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Material(
            color: Colors.white,
            child: TabBar(
              labelColor: burgundy,
              unselectedLabelColor: Color(0xFF64748B),
              indicatorColor: burgundy,
              tabs: [
                Tab(text: 'مباشر'),
                Tab(text: 'تقارير تفصيلية'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _LiveDesk(onOpenHr: onOpenHr),
                SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      AdminDailySalesCard(),
                      SizedBox(height: 16),
                      AdminProfitLossCard(),
                      SizedBox(height: 16),
                      AdminShiftReportsCard(),
                      SizedBox(height: 16),
                      AdminFoodCostReportPanel(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveDesk extends StatelessWidget {
  const _LiveDesk({this.onOpenHr});

  final VoidCallback? onOpenHr;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HrSummaryCard(onOpen: onOpenHr),
        const Expanded(child: AdminManagerReportsPanel()),
      ],
    );
  }
}
