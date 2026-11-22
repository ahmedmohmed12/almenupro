import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/kitchen_void_liability.dart';
import '../../../services/admin_auth_service.dart';
import '../../../services/pos_operations_service.dart';

class PosKitchenVoidLiabilitiesPage extends StatefulWidget {
  const PosKitchenVoidLiabilitiesPage({
    super.key,
    this.onPendingSummaryChanged,
    this.adminDashboard = false,
  });

  /// Called after each refresh so parent UI (e.g. tab badge) can update.
  final void Function(KitchenVoidLiabilitySummary summary)?
      onPendingSummaryChanged;

  /// Admin analytics tab: all restaurant records, pending first (not shift-scoped).
  final bool adminDashboard;

  @override
  State<PosKitchenVoidLiabilitiesPage> createState() =>
      _PosKitchenVoidLiabilitiesPageState();
}

class _PosKitchenVoidLiabilitiesPageState extends State<PosKitchenVoidLiabilitiesPage> {
  var _loading = true;
  var _busyId = '';
  String? _error;
  List<KitchenVoidLiability> _rows = const [];
  KitchenVoidLiabilitySummary _summary = const KitchenVoidLiabilitySummary();
  Timer? _timer;

  static const _burgundy = Color(0xFF6B1124);

  bool get _canReview => PosOperationsService.instance.canReviewRemoteApprovals();

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<KitchenVoidLiability> get _displayRows {
    if (!widget.adminDashboard) return _rows;
    final pending = _rows.where((row) => row.isPending).toList();
    if (pending.isNotEmpty) return pending;
    return _rows;
  }

  Future<void> _refresh() async {
    final shift = PosOperationsService.instance.activeShift;
    final canReview = _canReview;
    try {
      final result = await PosOperationsService.instance.fetchKitchenVoidLiabilities(
        shiftId: (widget.adminDashboard || canReview) ? null : shift?.id,
        status: widget.adminDashboard
            ? 'ALL'
            : (canReview ? 'PENDING' : 'ALL'),
      );
      if (!mounted) return;
      setState(() {
        _rows = result.liabilities;
        _summary = result.summary;
        _loading = false;
        _error = null;
      });
      widget.onPendingSummaryChanged?.call(result.summary);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _reviewerRoleId() {
    final cashier = PosOperationsService.instance.cashierSession;
    final roleId = cashier?.roleId.trim() ?? '';
    if (roleId.isNotEmpty) return roleId;
    final auth = AdminAuthService.instance;
    if (auth.isSuperAdmin) return 'super_admin';
    if (auth.isRestaurantAdmin) return 'restaurant_admin';
    return 'manager';
  }

  ({String? id, String? name}) _reviewerIdentity() {
    final cashier = PosOperationsService.instance.cashierSession;
    if (cashier != null) {
      return (id: cashier.staff.id, name: cashier.staff.name);
    }
    final auth = AdminAuthService.instance;
    return (
      id: auth.auditUserId,
      name: auth.auditUserName.isNotEmpty ? auth.auditUserName : 'مدير',
    );
  }

  Future<void> _review(KitchenVoidLiability row, {required bool approve}) async {
    final reviewer = _reviewerIdentity();
    setState(() => _busyId = row.id);
    try {
      await PosOperationsService.instance.reviewKitchenVoidLiability(
        row.id,
        approve: approve,
        reviewNote: approve ? 'موافقة (إعفاء الكاشير)' : 'مديونية على الكاشير',
        reviewedById: reviewer.id,
        reviewedByName: reviewer.name,
        roleId: _reviewerRoleId(),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busyId = '');
    }
  }

  Widget _pendingActions(KitchenVoidLiability row) {
    final busy = _busyId == row.id;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _burgundy,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            onPressed: busy ? null : () => _review(row, approve: true),
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_circle_outline, size: 20),
            label: const Text('موافقة (إعفاء)'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _burgundy,
              side: const BorderSide(color: _burgundy),
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            onPressed: busy ? null : () => _review(row, approve: false),
            icon: const Icon(Icons.money_off_csred_outlined, size: 20),
            label: const Text('رفض (مديونية)'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'مسؤوليات إلغاء أصناف المطبخ',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'الموافقة = إعفاء الكاشير؛ الرفض = مديونية تظهر عند إغلاق الوردية.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 4),
          Text(
            'معلّقة: ${_summary.pendingCount} (${_summary.pendingAmount.toStringAsFixed(3)} د.ك) — '
            'مديونية: ${_summary.rejectedAmount.toStringAsFixed(3)} د.ك',
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 12),
          if (widget.adminDashboard &&
              _summary.pendingCount == 0 &&
              _rows.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'لا توجد مسؤوليات معلّقة — قد تكون قد وُوفق عليها تلقائياً عند استخدام رمز المشرف.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ),
          if (_displayRows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('لا توجد مسؤوليات في القائمة الحالية')),
            ),
          for (final row in _displayRows)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(row.itemName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('كاشير: ${row.cashierName} — كمية: ${row.quantityRemoved}'),
                    Text(
                      'المبلغ: ${row.amount.toStringAsFixed(3)} د.ك — '
                      'منذ المطبخ: ${row.elapsedMinutes ?? '—'} د',
                    ),
                    Text('السبب: ${row.reason}'),
                    Text('الحالة: ${row.approvalStatus}'),
                    if (row.isPending && _canReview) _pendingActions(row),
                    if (row.isPending && !_canReview)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'لا توجد صلاحية مراجعة — سجّل دخول مدير أو مشرف.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}