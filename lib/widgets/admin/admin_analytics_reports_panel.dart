import 'package:flutter/material.dart';

import '../../services/admin_auth_service.dart';
import '../../services/super_admin_scope_service.dart';
import 'admin_daily_sales_card.dart';
import 'admin_food_cost_report_panel.dart';
import 'admin_responsive_layout.dart';
import 'admin_shift_reports_card.dart';

/// API-backed analytics reports scoped to the active restaurant.
class AdminAnalyticsReportsPanel extends StatelessWidget {
  const AdminAnalyticsReportsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = SuperAdminScopeService.instance;
    final isSuperAdmin = AdminAuthService.instance.isSuperAdmin;
    final needsSelection = isSuperAdmin && !scope.hasEffectiveRestaurant;

    return AdminResponsivePage(
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'التحليلات والمبيعات',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6B1124),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isSuperAdmin
                ? 'المطعم الحالي: ${scope.selectedRestaurantName ?? '—'}'
                : 'تقارير مبيعات وورديات محلّك',
          ),
          if (needsSelection) ...[
            const SizedBox(height: 12),
            const Text(
              'اختر مطعماً من قائمة المطاعم في الشريط الجانبي لعرض التقارير.',
              style: TextStyle(color: Colors.orange),
            ),
          ] else ...[
            const SizedBox(height: 20),
            const AdminDailySalesCard(),
            const SizedBox(height: 20),
            const AdminShiftReportsCard(),
            const SizedBox(height: 20),
            const AdminFoodCostReportPanel(),
          ],
        ],
      ),
    );
  }
}
