import 'package:flutter/material.dart';

import '../../../services/admin_auth_service.dart';
import '../../../services/manager_live_report_service.dart';
import '../../../services/super_admin_scope_service.dart';
import '../admin_breakpoints.dart';
import 'manager_owner_mobile_view.dart';
import 'manager_web_console.dart';

class AdminManagerReportsPanel extends StatefulWidget {
  const AdminManagerReportsPanel({super.key});

  @override
  State<AdminManagerReportsPanel> createState() =>
      _AdminManagerReportsPanelState();
}

class _AdminManagerReportsPanelState extends State<AdminManagerReportsPanel> {
  late final ManagerLiveReportService _live;
  final _scope = SuperAdminScopeService.instance;

  @override
  void initState() {
    super.initState();
    _live = ManagerLiveReportService();
    _scope.addListener(_onScope);
    _live.start(_restaurantId());
  }

  @override
  void dispose() {
    _scope.removeListener(_onScope);
    _live.dispose();
    super.dispose();
  }

  String _restaurantId() {
    if (AdminAuthService.instance.isRestaurantAdmin) {
      return AdminAuthService.instance.restaurantId ?? '';
    }
    return _scope.effectiveRestaurantId;
  }

  void _onScope() {
    final id = _restaurantId();
    if (id.isEmpty) return;
    _live.start(id);
  }

  @override
  Widget build(BuildContext context) {
    final mobile = AdminBreakpoints.widthOf(context) < 768;
    return AnimatedBuilder(
      animation: _live,
      builder: (context, _) {
        if (mobile) {
          return ManagerOwnerMobileView(
            snapshot: _live.snapshot,
            period: _live.period,
            onPeriodChanged: _live.setPeriod,
            onDismissAlert: _live.dismissAlert,
          );
        }
        return ManagerWebConsole(
          snapshot: _live.snapshot,
          period: _live.period,
          onPeriodChanged: _live.setPeriod,
          onDismissAlert: _live.dismissAlert,
        );
      },
    );
  }
}
