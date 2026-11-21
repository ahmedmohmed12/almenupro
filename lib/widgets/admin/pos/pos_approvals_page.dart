import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/pos_approval_request.dart';
import '../../../services/pos_operations_service.dart';

class PosApprovalsPage extends StatefulWidget {
  const PosApprovalsPage({super.key});

  @override
  State<PosApprovalsPage> createState() => _PosApprovalsPageState();
}

class _PosApprovalsPageState extends State<PosApprovalsPage> {
  var _loading = true;
  var _processingId = '';
  String? _error;
  List<PosApprovalRequest> _rows = const [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 12), (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final rows = await PosOperationsService.instance.fetchApprovalRequests(
        roleId: PosOperationsService.instance.cashierSession?.roleId,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  Future<void> _review(PosApprovalRequest row, {required bool approve}) async {
    final cashier = PosOperationsService.instance.cashierSession;
    final note = await _promptNote(approve);
    if (!mounted) return;
    if (!approve && note == null) return;

    setState(() => _processingId = row.id);
    try {
      if (approve) {
        await PosOperationsService.instance.approveApprovalRequest(
          row.id,
          reviewNote: note,
          reviewedById: cashier?.staff.id,
          reviewedByName: cashier?.staff.name,
          roleId: cashier?.roleId,
        );
      } else {
        await PosOperationsService.instance.rejectApprovalRequest(
          row.id,
          reviewNote: note ?? 'مرفوض',
          reviewedById: cashier?.staff.id,
          reviewedByName: cashier?.staff.name,
          roleId: cashier?.roleId,
        );
      }
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _processingId = '');
    }
  }

  Future<String?> _promptNote(bool approve) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'تأكيد الموافقة' : 'تأكيد الرفض'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: approve ? 'ملاحظة (اختياري)' : 'سبب الرفض',
            border: const OutlineInputBorder(),
          ),
          minLines: 1,
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (!PosOperationsService.instance.canReviewRemoteApprovals()) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('الموافقات عن بُعد متاحة لمشرف الوردية أو المدير فقط'),
        ),
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'طلبات الموافقة عن بُعد',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          if (_rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('لا توجد طلبات قيد الانتظار')),
            ),
          for (final row in _rows) _ApprovalCard(
            row: row,
            busy: _processingId == row.id,
            onApprove: () => _review(row, approve: true),
            onReject: () => _review(row, approve: false),
          ),
        ],
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.row,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final PosApprovalRequest row;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final payload = row.payload;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(row.typeLabelAr, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('الكاشير: ${row.requestedByName}'),
            Text('السبب: ${row.reason}'),
            if (payload['itemName'] != null)
              Text('الصنف: ${payload['itemName']}'),
            if (payload['orderId'] != null) Text('الطلب: ${payload['orderId']}'),
            if (payload['total'] != null)
              Text('طلبات معلّقة: ${payload['total']}'),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton(
                  onPressed: busy ? null : onApprove,
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('موافقة'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: busy ? null : onReject,
                  child: const Text('رفض'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}