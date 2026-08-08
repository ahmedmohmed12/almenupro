import 'package:flutter/material.dart';

import '../../models/shift_session.dart';
import '../../services/admin_auth_service.dart';
import '../../services/pos_operations_service.dart';
import '../../services/super_admin_scope_service.dart';
import 'admin_responsive_layout.dart';
import 'pos/pos_close_shift_dialog.dart';

class AdminShiftReportsCard extends StatefulWidget {
  const AdminShiftReportsCard({super.key});

  @override
  State<AdminShiftReportsCard> createState() => _AdminShiftReportsCardState();
}

class _AdminShiftReportsCardState extends State<AdminShiftReportsCard> {
  var _loading = true;
  String? _error;
  ShiftReportsResult _result = const ShiftReportsResult(shifts: []);
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
      return AdminAuthService.instance.restaurantId ?? '';
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
        _result = const ShiftReportsResult(shifts: []);
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
      final from = DateTime.now().toUtc().subtract(const Duration(days: 30));
      final result = await PosOperationsService.instance.fetchShiftReports(
        restaurantId: restaurantId,
        from: from,
        includeOpen: true,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
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

  String? _emptyStateMessage() {
    final meta = _result.meta;
    switch (meta.dataState) {
      case 'open_shifts_only':
        return 'لا توجد ورديات مغلقة — لكن هناك ${meta.openCount} وردية مفتوحة بمبيعات حية.';
      case 'orders_without_shifts':
        return 'يوجد ${meta.ordersInRange} طلب في آخر 30 يوم (${meta.ordersWithoutShift} بدون وردية) — أغلق وردية POS لإنشاء تقرير جرد.';
      case 'no_activity':
        return 'لا توجد ورديات أو طلبات POS في آخر 30 يوم.';
      default:
        return null;
    }
  }

  Widget _buildShiftTile(ShiftSession shift, {required bool isOpen}) {
    final summary = shift.summary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        '${shift.cashierName} — ${isOpen ? 'مفتوحة' : shift.closedAt?.toLocal().toString().substring(0, 16) ?? ''}',
      ),
      subtitle: Text(
        'طلبات: ${summary.orderCount} • كاش: ${summary.cashSales.toStringAsFixed(3)} • K-Net: ${summary.knetSales.toStringAsFixed(3)}'
        '${isOpen ? '' : ' • فرق: ${summary.discrepancyLabelAr} ${summary.discrepancy.toStringAsFixed(3)}'}',
      ),
      trailing: IconButton(
        icon: const Icon(Icons.visibility_outlined),
        onPressed: () => showShiftSummaryDialog(context, shift),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final closedShifts = _result.closedShifts;
    final openShifts = _result.openShifts;
    final emptyMessage = _emptyStateMessage();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF6B1124)))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminSectionHeader(
                    icon: Icons.receipt_long,
                    title: 'تقارير إغلاق الورديات',
                    subtitle: 'جرد مالي لكل وردية — كاش، K-Net، فروقات',
                    actions: [
                      IconButton(
                        tooltip: 'تحديث',
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red))
                  else if (!_canLoad)
                    const Text(
                      'اختر مطعماً لعرض تقارير الورديات.',
                      style: TextStyle(color: Color(0xFF888888)),
                    )
                  else if (closedShifts.isEmpty && openShifts.isEmpty)
                    Text(
                      emptyMessage ?? 'لا توجد ورديات مغلقة في آخر 30 يوم',
                      style: const TextStyle(color: Color(0xFF888888)),
                    )
                  else ...[
                    if (closedShifts.isNotEmpty) ...[
                      const Text(
                        'ورديات مغلقة',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...closedShifts.take(20).map(
                            (shift) => _buildShiftTile(shift, isOpen: false),
                          ),
                    ] else if (emptyMessage != null) ...[
                      Text(
                        emptyMessage,
                        style: const TextStyle(color: Color(0xFF888888)),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (openShifts.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'ورديات مفتوحة (لم تُغلق بعد)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...openShifts.take(10).map(
                            (shift) => _buildShiftTile(shift, isOpen: true),
                          ),
                    ],
                  ],
                ],
              ),
      ),
    );
  }
}
