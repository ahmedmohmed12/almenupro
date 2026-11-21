import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/pos_operations_service.dart';
import '../../../utils/kitchen_dispatch.dart';

Future<KitchenOverrideAuthorization?> showPosKitchenLineOverrideDialog(
  BuildContext context, {
  required String itemName,
  required String actionLabel,
  String? entityId,
}) {
  return showDialog<KitchenOverrideAuthorization>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _KitchenLineOverrideDialog(
      itemName: itemName,
      actionLabel: actionLabel,
      entityId: entityId,
    ),
  );
}

class _KitchenLineOverrideDialog extends StatefulWidget {
  const _KitchenLineOverrideDialog({
    required this.itemName,
    required this.actionLabel,
    this.entityId,
  });

  final String itemName;
  final String actionLabel;
  final String? entityId;

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

  Future<void> _submit() async {
    final pin = _pinController.text.trim();
    if (pin.length < 4) {
      setState(() => _error = 'أدخل رمز PIN للمشرف');
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
        reason: _resolvedReason,
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
            TextField(
              controller: _pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'PIN المشرف / مدير الفرع',
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
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('تأكيد'),
        ),
      ],
    );
  }
}