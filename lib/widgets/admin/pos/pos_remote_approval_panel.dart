import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../models/pos_approval_request.dart';
import '../../../services/pos_operations_service.dart';

typedef PosRemoteApprovalResolved = void Function(PosApprovalRequest request);

class PosRemoteApprovalPanel extends StatefulWidget {
  const PosRemoteApprovalPanel({
    super.key,
    required this.approvalType,
    required this.reason,
    required this.shiftId,
    required this.payload,
    this.onApproved,
    this.onRejected,
    this.onExpired,
  });

  final String approvalType;
  final String reason;
  final String shiftId;
  final Map<String, dynamic> payload;
  final PosRemoteApprovalResolved? onApproved;
  final VoidCallback? onRejected;
  final VoidCallback? onExpired;

  @override
  State<PosRemoteApprovalPanel> createState() => _PosRemoteApprovalPanelState();
}

class _PosRemoteApprovalPanelState extends State<PosRemoteApprovalPanel> {
  PosApprovalRequest? _request;
  var _submitting = false;
  var _polling = false;
  String? _error;
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _send() async {
    if (widget.reason.trim().length < 3) {
      setState(() => _error = 'أدخل سبباً واضحاً (3 أحرف على الأقل)');
      return;
    }
    final cashier = PosOperationsService.instance.cashierSession;
    final shiftId = widget.shiftId.trim().isNotEmpty
        ? widget.shiftId.trim()
        : (PosOperationsService.instance.activeShift?.id ?? '');
    if (shiftId.isEmpty) {
      setState(() => _error = 'لا توجد وردية مفتوحة');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final created = await PosOperationsService.instance.createApprovalRequest(
        type: widget.approvalType,
        reason: widget.reason.trim(),
        shiftId: shiftId,
        payload: widget.payload,
        requestedById: cashier?.staff.id,
        requestedByName: cashier?.staff.name,
      );
      if (!mounted) return;
      setState(() {
        _request = created;
        _submitting = false;
      });
      _startPolling();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _checkStatus());
    unawaited(_checkStatus());
  }

  Future<void> _checkStatus() async {
    final id = _request?.id;
    if (id == null || id.isEmpty) return;
    if (_polling) return;
    _polling = true;
    try {
      final fresh = await PosOperationsService.instance.fetchApprovalRequest(id);
      if (!mounted) return;
      setState(() => _request = fresh);
      if (fresh.isApproved) {
        _pollTimer?.cancel();
        widget.onApproved?.call(fresh);
      } else if (fresh.isRejected) {
        _pollTimer?.cancel();
        widget.onRejected?.call();
      } else if (fresh.isExpired) {
        _pollTimer?.cancel();
        widget.onExpired?.call();
      }
    } catch (_) {
      // Keep polling on transient errors.
    } finally {
      _polling = false;
    }
  }

  Future<void> _cancel() async {
    final id = _request?.id;
    if (id == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await PosOperationsService.instance.cancelApprovalRequest(id);
      _pollTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _request = null;
        _submitting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_request == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'طلب موافقة عن بُعد',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'يُرسل الطلب لمدير الفرع أو مشرف الوردية للموافقة من جهاز آخر.',
            style: TextStyle(fontSize: 12),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _submitting ? null : _send,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('إرسال طلب الموافقة'),
          ),
        ],
      );
    }

    final status = _request!.status.toUpperCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.hourglass_top_rounded, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'بانتظار موافقة المشرف/المدير… ($status)',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('رقم الطلب: ${_request!.id}'),
        if (_request!.isRejected) ...[
          const SizedBox(height: 8),
          Text(
            _request!.reviewNote ?? 'تم رفض الطلب',
            style: const TextStyle(color: Colors.red),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton(
              onPressed: _polling ? null : _checkStatus,
              child: const Text('تحديث الحالة'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _submitting ? null : _cancel,
              child: const Text('إلغاء الطلب'),
            ),
          ],
        ),
      ],
    );
  }
}