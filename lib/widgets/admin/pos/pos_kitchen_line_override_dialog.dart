import 'package:flutter/material.dart';

import '../../../utils/kitchen_dispatch.dart';

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
  final _otherReasonController = TextEditingController();
  String _reason = KitchenVoidReason.entryMistake;
  bool _otherSelected = false;
  String? _error;

  @override
  void dispose() {
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

  void _submitConditional() {
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تعديل صنف أُرسل للمطبخ'),
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
            const SizedBox(height: 10),
            const Text(
              'يُسجَّل إلغاء/تقليل المطبخ كمسؤولية معلّقة. الموافقة (إعفاء) أو الرفض (مديونية) من لوحة الإدارة فقط.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
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
                    _error = null;
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
                decoration: InputDecoration(
                  labelText: 'اذكر السبب',
                  border: const OutlineInputBorder(),
                  errorText: _error,
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 8),
            ] else if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _submitConditional,
          child: const Text('تأكيد (مسؤولية معلّقة)'),
        ),
      ],
    );
  }
}