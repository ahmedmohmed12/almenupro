import 'package:flutter/material.dart';

import '../../../models/shift_session.dart';
import '../../../services/pos_operations_service.dart';

Future<ShiftSession?> showPosCloseShiftDialog(
  BuildContext context, {
  required ShiftSession shift,
}) {
  return showDialog<ShiftSession>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _PosCloseShiftDialog(shift: shift),
  );
}

class _PosCloseShiftDialog extends StatefulWidget {
  const _PosCloseShiftDialog({required this.shift});

  final ShiftSession shift;

  @override
  State<_PosCloseShiftDialog> createState() => _PosCloseShiftDialogState();
}

class _PosCloseShiftDialogState extends State<_PosCloseShiftDialog> {
  final _cashController = TextEditingController();
  final _notesController = TextEditingController();
  var _submitting = false;
  String? _error;

  @override
  void dispose() {
    _cashController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final counted = double.tryParse(_cashController.text.trim());
    if (counted == null) {
      setState(() => _error = 'أدخل مبلغ النقد الفعلي في الدرج');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final cashier = PosOperationsService.instance.cashierSession;
      final closed = await PosOperationsService.instance.closeShift(
        shiftId: widget.shift.id,
        closingCashCounted: counted,
        notes: _notesController.text.trim(),
        closedById: cashier?.staff.id,
        closedByName: cashier?.staff.name,
      );
      if (!mounted) return;
      Navigator.of(context).pop(closed);
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
      title: const Text('إغلاق الوردية — جرد مالي'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('الكاشير: ${widget.shift.cashierName}'),
            Text('افتتاح الدرج: ${widget.shift.openingFloat.toStringAsFixed(3)} د.ك'),
            const SizedBox(height: 12),
            TextField(
              controller: _cashController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'النقد الفعلي المعدود في الدرج',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'ملاحظات (اختياري)',
                border: OutlineInputBorder(),
              ),
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
              : const Text('إغلاق الوردية'),
        ),
      ],
    );
  }
}

Future<void> showShiftSummaryDialog(BuildContext context, ShiftSession shift) {
  final summary = shift.summary;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('ملخص الوردية'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _summaryRow('عدد الطلبات', '${summary.orderCount}'),
          _summaryRow('مبيعات كاش', '${summary.cashSales.toStringAsFixed(3)} د.ك'),
          _summaryRow('مبيعات K-Net', '${summary.knetSales.toStringAsFixed(3)} د.ك'),
          _summaryRow('مبيعات إلكترونية', '${summary.electronicSales.toStringAsFixed(3)} د.ك'),
          _summaryRow('مرتجعات', '${summary.refundTotal.toStringAsFixed(3)} د.ك'),
          _summaryRow('إلغاءات', '${summary.voidCount}'),
          const Divider(),
          _summaryRow('النقد المتوقع', '${summary.expectedCash.toStringAsFixed(3)} د.ك'),
          _summaryRow('النقد الفعلي', '${summary.actualCash.toStringAsFixed(3)} د.ك'),
          _summaryRow(
            'الفرق (${summary.discrepancyLabelAr})',
            '${summary.discrepancy.toStringAsFixed(3)} د.ك',
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('تم'),
        ),
      ],
    ),
  );
}

Widget _summaryRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    ),
  );
}
