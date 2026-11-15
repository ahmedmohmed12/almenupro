import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/staff_user.dart';
import '../../../services/pos_operations_service.dart';

Future<ManagerOverrideResult?> showPosManagerOverrideDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  String? entityId,
}) {
  return showDialog<ManagerOverrideResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _PosManagerOverrideDialog(
      title: title,
      message: message,
      action: action,
      entityId: entityId,
    ),
  );
}

class _PosManagerOverrideDialog extends StatefulWidget {
  const _PosManagerOverrideDialog({
    required this.title,
    required this.message,
    required this.action,
    this.entityId,
  });

  final String title;
  final String message;
  final String action;
  final String? entityId;

  @override
  State<_PosManagerOverrideDialog> createState() => _PosManagerOverrideDialogState();
}

class _PosManagerOverrideDialogState extends State<_PosManagerOverrideDialog> {
  final _pinController = TextEditingController();
  var _submitting = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();
    if (pin.length < 4) {
      setState(() => _error = 'أدخل رمز PIN للمشرف');
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
        action: widget.action,
        entityId: widget.entityId,
        performedById: cashier?.staff.id,
        performedByName: cashier?.staff.name,
      );
      if (!mounted) return;
      if (!result.authorized) {
        setState(() => _error = 'رمز غير صحيح أو غير مصرح');
        return;
      }
      Navigator.of(context).pop(result);
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
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.message),
          const SizedBox(height: 16),
          TextField(
            controller: _pinController,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'رمز PIN للمشرف',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
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
              : const Text('تفويض'),
        ),
      ],
    );
  }
}
