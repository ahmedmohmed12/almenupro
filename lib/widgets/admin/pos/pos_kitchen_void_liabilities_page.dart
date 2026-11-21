import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/kitchen_void_liability.dart';
import '../../../services/pos_operations_service.dart';

class PosKitchenVoidLiabilitiesPage extends StatefulWidget {
  const PosKitchenVoidLiabilitiesPage({super.key});

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

  Future<void> _refresh() async {
    final shift = PosOperationsService.instance.activeShift;
    final cashier = PosOperationsService.instance.cashierSession;
    final manager = PosOperationsService.instance.canReviewRemoteApprovals();
    try {
      final result = await PosOperationsService.instance.fetchKitchenVoidLiabilities(
        shiftId: shift?.id,
        cashierId: manager ? null : cashier?.staff.id,
        status: manager ? 'PENDING' : 'ALL',
      );
      if (!mounted) return;
      setState(() {
        _rows = result.liabilities;
        _summary = result.summary;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _review(KitchenVoidLiability row, {required bool approve}) async {
    final cashier = PosOperationsService.instance.cashierSession;
    setState(() => _busyId = row.id);
    try {
      await PosOperationsService.instance.reviewKitchenVoidLiability(
        row.id,
        approve: approve,
        reviewNote: approve ? 'موافقة' : 'مديونية على الكاشير',
        reviewedById: cashier?.staff.id,
        reviewedByName: cashier?.staff.name,
        roleId: cashier?.roleId,
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

  @override
  Widget build(BuildContext context) {
    final manager = PosOperationsService.instance.canReviewRemoteApprovals();
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
          if (_rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('لا توجد مسؤوليات في القائمة الحالية')),
            ),
          for (final row in _rows)
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
                    if (manager && row.isPending) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          FilledButton(
                            onPressed: _busyId == row.id
                                ? null
                                : () => _review(row, approve: true),
                            child: const Text('موافقة (إعفاء)'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _busyId == row.id
                                ? null
                                : () => _review(row, approve: false),
                            child: const Text('رفض (مديونية)'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}