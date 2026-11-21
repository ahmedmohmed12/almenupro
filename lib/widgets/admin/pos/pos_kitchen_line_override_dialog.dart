import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/pos_approval_request.dart';
import '../../../services/pos_operations_service.dart';
import '../../../utils/kitchen_dispatch.dart';
import 'pos_remote_approval_panel.dart';

Future<KitchenOverrideAuthorization?> showPosKitchenLineOverrideDialog(
  BuildContext context, {
  required String itemName,
  required String actionLabel,
  String? entityId,
  String? orderId,
  String? cartItemId,
  int? previousQuantity,
  int? nextQuantity,
  String? shiftId,
}) {
  return showDialog<KitchenOverrideAuthorization>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _KitchenLineOverrideDialog(
      itemName: itemName,
      actionLabel: actionLabel,
      entityId: entityId,
      orderId: orderId,
      cartItemId: cartItemId,
      previousQuantity: previousQuantity,
      nextQuantity: nextQuantity,
      shiftId: shiftId,
    ),
  );
}

class _KitchenLineOverrideDialog extends StatefulWidget {
  const _KitchenLineOverrideDialog({
    required this.itemName,
    required this.actionLabel,
    this.entityId,
    this.orderId,
    this.cartItemId,
    this.previousQuantity,
    this.nextQuantity,
    this.shiftId,
  });

  final String itemName;
  final String actionLabel;
  final String? entityId;
  final String? orderId;
  final String? cartItemId;
  final int? previousQuantity;
  final int? nextQuantity;
  final String? shiftId;

  @override
  State<_KitchenLineOverrideDialog> createState() =>
      _KitchenLineOverrideDialogState();
}

class _KitchenLineOverrideDialogState extends State<_KitchenLineOverrideDialog> {
  final _pinController = TextEditingController();
  final _otherReasonController = TextEditingController();
  String _reason = KitchenVoidReason.entryMistake;
  bool _otherSelected = false;
  var _submitting = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _otherReasonController.dispose();
    super.dispose();
  }

  String get _resolvedReason {
    if (_otherSelected) {
      final custom = _otherReasonController.text.trim();
      if (custom.isEmpty) return KitchenVoidReason.other;
      return custom;
    }
    return _reason;
  }

  Map<String, dynamic> get _approvalPayload => {
        'orderId': widget.orderId ?? widget.entityId,
        'cartItemId': widget.cartItemId,
        'itemName': widget.itemName,
        if (widget.previousQuantity != null)
          'previousQuantity': widget.previousQuantity,
        if (widget.nextQuantity != null) 'nextQuantity': widget.nextQuantity,
        'actionLabel': widget.actionLabel,
      };

  void _completeRemote(PosApprovalRequest request) {
    Navigator.of(context).pop(
      KitchenOverrideAuthorization(
        reason: _resolvedReason,
        approvalRequestId: request.id,
        cartItemId: widget.cartItemId,
        authorizedById: request.reviewedById,
        authorizedByName: request.reviewedByName,
      ),
    );
  }

  Future<void> _submitConditional() async {
    if (_otherSelected && _otherReasonController.text.trim().isEmpty) {
      setState(() => _error = 'أدخل السبب');
      return;
    }
    Navigator.of(context).pop(
      KitchenOverrideAuthorization(
        reason: _resolvedReason,
        cartItemId: widget.cartItemId,
      ),
    );
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();
    if (pin.length < 4) {
      setState(() => _error = 'أدخل رمز PIN للمشرف أو استخدم التأكيد مع مسؤولية معلّقة');
      return;
    }
    if (_otherSelected && _otherReasonController.text.trim().isEmpty) {
      setState(() => _error = 'أدخل السبب');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final cashier = PosOperationsService.instance.cashierSession;
      final result = await PosOperationsService.instance.requestManagerOverride(
        pin: pin,
        action: 'kitchen_line_void',
        entityId: widget.entityId,
        performedById: cashier?.staff.id,
        performedByName: cashier?.staff.name,
      );
      if (!mounted) return;
      if (!result.authorized) {
        setState(() => _error = 'رمز غير صحيح أو غير مصرح');
        return;
      }
      Navigator.of(context).pop(
        KitchenOverrideAuthorization(
          managerPin: pin,
          reason: _resolvedReason,
          authorizedById: result.authorizedById,
          authorizedByName: result.authorizedByName,
          cartItemId: widget.cartItemId,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shiftId =
        widget.shiftId ?? PosOperationsService.instance.activeShift?.id ?? '';

    return AlertDialog(
      title: const Text('تفويض مشرف — صنف بالمطبخ'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.actionLabel),
            const SizedBox(height: 6),
            Text(
              widget.itemName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            const Text('سبب التعديل/الإلغاء'),
            ...KitchenVoidReason.options.entries.map(
              (entry) => RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value),
                value: entry.key,
                groupValue: _otherSelected ? null : _reason,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _reason = value;
                    _otherSelected = false;
                  });
                },
              ),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _otherSelected,
              onChanged: (checked) =>
                  setState(() => _otherSelected = checked == true),
              title: const Text('سبب آخر'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_otherSelected) ...[
              TextField(
                controller: _otherReasonController,
                decoration: const InputDecoration(
                  labelText: 'اذكر السبب',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
            ],
            const Divider(),
            PosRemoteApprovalPanel(
              approvalType: PosApprovalTypes.voidSentItem,
              reason: _otherSelected
                  ? _otherReasonController.text.trim()
                  : (KitchenVoidReason.options[_reason] ?? _reason),
              shiftId: shiftId,
              payload: _approvalPayload,
              onApproved: _completeRemote,
              onRejected: () => setState(
                () => _error = 'رفض المشرف طلب الموافقة عن بُعد',
              ),
              onExpired: () => setState(
                () => _error = 'انتهت صلاحية طلب الموافقة',
              ),
            ),
            const Divider(),
            TextField(
              controller: _pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'PIN المشرف / مدير الفرع (حضورياً)',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton.tonal(
          onPressed: _submitting ? null : _submitConditional,
          child: const Text('تأكيد (مسؤولية معلّقة)'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('تأكيد PIN'),
        ),
      ],
    );
  }
}