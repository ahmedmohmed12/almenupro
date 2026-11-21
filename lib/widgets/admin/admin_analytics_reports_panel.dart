import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/admin_auth_service.dart';
import '../../services/pos_operations_service.dart';
import '../../services/super_admin_scope_service.dart';
import 'admin_daily_sales_card.dart';
import 'admin_food_cost_report_panel.dart';
import 'admin_profit_loss_card.dart';
import 'admin_shift_reports_card.dart';
import 'hr/hr_summary_card.dart';
import 'manager/admin_manager_reports_panel.dart';
import 'pos/pos_kitchen_void_liabilities_page.dart';

class AdminAnalyticsReportsPanel extends StatefulWidget {
  const AdminAnalyticsReportsPanel({
    super.key,
    this.onOpenHr,
    this.showKitchenVoidTab = false,
  });

  static const burgundy = Color(0xFF6B1124);
  final VoidCallback? onOpenHr;
  final bool showKitchenVoidTab;

  @override
  State<AdminAnalyticsReportsPanel> createState() =>
      _AdminAnalyticsReportsPanelState();
}

class _AdminAnalyticsReportsPanelState extends State<AdminAnalyticsReportsPanel> {
  Timer? _pendingBadgeTimer;
  var _pendingCount = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPendingBadgePoll();
  }

  @override
  void didUpdateWidget(covariant AdminAnalyticsReportsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showKitchenVoidTab != widget.showKitchenVoidTab) {
      _syncPendingBadgePoll();
    }
  }

  void _syncPendingBadgePoll() {
    _pendingBadgeTimer?.cancel();
    _pendingBadgeTimer = null;
    if (!widget.showKitchenVoidTab) return;
    unawaited(_refreshPendingBadge());
    _pendingBadgeTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_refreshPendingBadge()),
    );
  }

  Future<void> _refreshPendingBadge() async {
    try {
      final result =
          await PosOperationsService.instance.fetchKitchenVoidLiabilities(
        status: 'PENDING',
      );
      if (!mounted) return;
      final next = result.summary.pendingCount;
      if (next != _pendingCount) {
        setState(() => _pendingCount = next);
      }
    } catch (_) {
      // Tab badge is optional; page tab still works.
    }
  }

  @override
  void dispose() {
    _pendingBadgeTimer?.cancel();
    super.dispose();
  }

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

    final tabCount = widget.showKitchenVoidTab ? 3 : 2;

    return DefaultTabController(
      length: tabCount,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.white,
            child: TabBar(
              labelColor: AdminAnalyticsReportsPanel.burgundy,
              unselectedLabelColor: const Color(0xFF64748B),
              indicatorColor: AdminAnalyticsReportsPanel.burgundy,
              tabs: [
                const Tab(text: 'مباشر'),
                const Tab(text: 'تقارير تفصيلية'),
                if (widget.showKitchenVoidTab)
                  Tab(
                    child: _KitchenVoidTabLabel(pendingCount: _pendingCount),
                  ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _LiveDesk(onOpenHr: widget.onOpenHr),
                const SingleChildScrollView(
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
                if (widget.showKitchenVoidTab)
                  const PosKitchenVoidLiabilitiesPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KitchenVoidTabLabel extends StatelessWidget {
  const _KitchenVoidTabLabel({required this.pendingCount});

  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final label = const Text('مسؤوليات إلغاء المطبخ');
    if (pendingCount <= 0) return label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        label,
        const SizedBox(width: 6),
        Badge(
          label: Text('$pendingCount'),
          backgroundColor: AdminAnalyticsReportsPanel.burgundy,
        ),
      ],
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