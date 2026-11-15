import 'package:flutter/material.dart';

import '../../models/shift_session.dart';
import '../../services/admin_auth_service.dart';
import '../../services/pos_operations_service.dart';
import '../../services/super_admin_scope_service.dart';
import 'admin_responsive_layout.dart';
import 'pos/pos_close_shift_dialog.dart';

class AdminShiftReportsCard extends StatefulWidget {
  const AdminShiftReportsCard({
    super.key,
    this.cashierOnly = false,
  });

  /// When true (cashier POS), show only the logged-in cashier's current + past shifts.
  final bool cashierOnly;

  @override
  State<AdminShiftReportsCard> createState() => _AdminShiftReportsCardState();
}

class _AdminShiftReportsCardState extends State<AdminShiftReportsCard> {
  var _loading = true;
  String? _error;
  ShiftReportsResult _result = const ShiftReportsResult(shifts: []);
  ShiftSession? _currentShift;
  String? _loadedRestaurantId;
  String? _loadedCashierId;

  @override
  void initState() {
    super.initState();
    _load();
    SuperAdminScopeService.instance.addListener(_onScopeChanged);
    if (widget.cashierOnly) {
      PosOperationsService.instance.addListener(_onPosSessionChanged);
    }
  }

  @override
  void dispose() {
    SuperAdminScopeService.instance.removeListener(_onScopeChanged);
    if (widget.cashierOnly) {
      PosOperationsService.instance.removeListener(_onPosSessionChanged);
    }
    super.dispose();
  }

  void _onScopeChanged() {
    final nextId = _resolveRestaurantId();
    if (nextId != _loadedRestaurantId) {
      _load();
    }
  }

  void _onPosSessionChanged() {
    final nextCashier = _resolveCashierId();
    if (nextCashier != _loadedCashierId) {
      _load();
    }
  }

  String _resolveRestaurantId() {
    if (AdminAuthService.instance.isRestaurantAdmin ||
        AdminAuthService.instance.isCashier) {
      return AdminAuthService.instance.restaurantId ?? '';
    }
    return SuperAdminScopeService.instance.effectiveRestaurantId;
  }

  String? _resolveCashierId() {
    if (!widget.cashierOnly) return null;
    final fromPos = PosOperationsService.instance.cashierSession?.staff.id.trim();
    if (fromPos != null && fromPos.isNotEmpty) return fromPos;
    final fromAuth = AdminAuthService.instance.session?.staffId?.trim();
    if (fromAuth != null && fromAuth.isNotEmpty) return fromAuth;
    return null;
  }

  bool get _canLoad {
    if (widget.cashierOnly) {
      return _resolveRestaurantId().isNotEmpty &&
          (_resolveCashierId()?.isNotEmpty ?? false);
    }
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
        _currentShift = null;
        _loadedRestaurantId = null;
        _loadedCashierId = null;
      });
      return;
    }

    final restaurantId = _resolveRestaurantId();
    final cashierId = _resolveCashierId();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final from = widget.cashierOnly
          ? null
          : DateTime.now().toUtc().subtract(const Duration(days: 30));
      final reportsFuture = PosOperationsService.instance.fetchShiftReports(
        restaurantId: restaurantId,
        cashierId: cashierId,
        from: from,
        includeOpen: true,
      );
      final currentFuture = widget.cashierOnly && cashierId != null
          ? PosOperationsService.instance.fetchCurrentShift(cashierId: cashierId)
          : Future<ShiftSession?>.value(null);

      final results = await Future.wait([reportsFuture, currentFuture]);
      if (!mounted) return;
      final result = results[0] as ShiftReportsResult;
      var current = results[1] as ShiftSession?;
      if (current == null) {
        for (final shift in result.openShifts) {
          if (cashierId == null || shift.cashierId == cashierId) {
            current = shift;
            break;
          }
        }
      }

      setState(() {
        _result = result;
        _currentShift = current;
        _loadedRestaurantId = restaurantId;
        _loadedCashierId = cashierId;
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

  List<ShiftSession> get _previousClosedShifts {
    final currentId = _currentShift?.id;
    return _result.closedShifts
        .where((shift) => currentId == null || shift.id != currentId)
        .toList();
  }

  Widget _buildShiftTile(ShiftSession shift, {required bool isOpen}) {
    final summary = shift.summary;
    final subtitle = widget.cashierOnly
        ? 'كاش ${summary.cashSales.toStringAsFixed(3)} • K-Net ${summary.knetSales.toStringAsFixed(3)} • '
            'طاولات ${summary.dineInCount} • سفري ${summary.takeawayCount} • موقع ${summary.websiteCount}'
        : 'طلبات: ${summary.orderCount} • كاش: ${summary.cashSales.toStringAsFixed(3)} • توصيل: ${summary.deliveryExpenses.toStringAsFixed(3)}'
            '${isOpen ? '' : ' • فرق: ${summary.discrepancyLabelAr} ${summary.discrepancy.toStringAsFixed(3)}'}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: const Color(0xFFF7F7F8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Text(
          widget.cashierOnly
              ? (isOpen
                  ? 'وردية مفتوحة'
                  : (shift.closedAt?.toLocal().toString().substring(0, 16) ??
                      'وردية مغلقة'))
              : '${shift.cashierName} — ${isOpen ? 'مفتوحة' : shift.closedAt?.toLocal().toString().substring(0, 16) ?? ''}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        trailing: IconButton(
          icon: const Icon(Icons.visibility_outlined),
          tooltip: 'التفاصيل',
          onPressed: () => showShiftSummaryDialog(context, shift),
        ),
        onTap: () => showShiftSummaryDialog(context, shift),
      ),
    );
  }

  Widget _buildCurrentShiftCard(ShiftSession shift) {
    final summary = shift.summary;
    final expectedCash = shift.openingFloat +
        summary.cashSales -
        summary.refundTotal -
        summary.deliveryExpenses;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6B1124).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.point_of_sale, color: Color(0xFF6B1124)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'الوردية الحالية',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF6B1124),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => showShiftSummaryDialog(context, shift),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('التفاصيل'),
              ),
            ],
          ),
          Text(
            'الكاشير: ${shift.cashierName}',
            style: const TextStyle(color: Color(0xFF555555)),
          ),
          Text(
            'افتتحت: ${shift.openedAt.toLocal().toString().substring(0, 16)}',
            style: const TextStyle(color: Color(0xFF777777), fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metricChip('النقد المتوقع بالدرج', expectedCash),
              _metricChip('مبيعات كاش', summary.cashSales),
              _metricChip('مبيعات K-Net', summary.knetSales),
              _metricChip('إجمالي المبيعات', summary.grossSales),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'تفصيل القنوات',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          shiftSummaryChannelRows(summary),
          const SizedBox(height: 8),
          const Divider(),
          shiftSummaryPaymentRows(summary, openingFloat: shift.openingFloat),
          const SizedBox(height: 8),
          Text(
            'عند إغلاق الوردية يُفترض تسليم نقد الدرج: ${expectedCash.toStringAsFixed(3)} د.ك',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B1124),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricChip(String label, double value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE6E6E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF777777))),
          Text(
            '${value.toStringAsFixed(3)} د.ك',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final closedShifts =
        widget.cashierOnly ? _previousClosedShifts : _result.closedShifts;
    final openShifts = widget.cashierOnly
        ? _result.openShifts
            .where((shift) => _currentShift == null || shift.id != _currentShift!.id)
            .toList()
        : _result.openShifts;
    final emptyMessage = _emptyStateMessage();
    final hasCurrent = _currentShift != null;
    final hasAny = hasCurrent || closedShifts.isNotEmpty || openShifts.isNotEmpty;

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
                    title: widget.cashierOnly
                        ? 'تقارير ورديتي'
                        : 'تقارير إغلاق الورديات',
                    subtitle: widget.cashierOnly
                        ? 'الوردية الحالية + الورديات السابقة الخاصة بك — كاش، K-Net، طاولات، سفري، موقع'
                        : 'جرد مالي لكل وردية — كاش، K-Net، فروقات',
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
                    Text(
                      widget.cashierOnly
                          ? 'سجّل دخول الكاشير لعرض تقارير ورديتك.'
                          : 'اختر مطعماً لعرض تقارير الورديات.',
                      style: const TextStyle(color: Color(0xFF888888)),
                    )
                  else if (!hasAny)
                    Text(
                      emptyMessage ??
                          (widget.cashierOnly
                              ? 'لا توجد وردية حالية أو سابقة لهذا الكاشير.'
                              : 'لا توجد ورديات مغلقة في آخر 30 يوم'),
                      style: const TextStyle(color: Color(0xFF888888)),
                    )
                  else ...[
                    if (widget.cashierOnly && hasCurrent) ...[
                      _buildCurrentShiftCard(_currentShift!),
                      const SizedBox(height: 16),
                    ],
                    if (closedShifts.isNotEmpty) ...[
                      Text(
                        widget.cashierOnly
                            ? 'الورديات السابقة'
                            : 'ورديات مغلقة',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...closedShifts.take(widget.cashierOnly ? 50 : 20).map(
                            (shift) => _buildShiftTile(shift, isOpen: false),
                          ),
                    ] else if (widget.cashierOnly && hasCurrent) ...[
                      const Text(
                        'لا توجد ورديات سابقة مغلقة بعد.',
                        style: TextStyle(color: Color(0xFF888888)),
                      ),
                    ] else if (emptyMessage != null) ...[
                      Text(
                        emptyMessage,
                        style: const TextStyle(color: Color(0xFF888888)),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!widget.cashierOnly && openShifts.isNotEmpty) ...[
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
