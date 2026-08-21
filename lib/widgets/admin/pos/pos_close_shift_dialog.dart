import 'package:flutter/material.dart';

import '../../../models/order.dart';
import '../../../models/shift_session.dart';
import '../../../services/api_service.dart';
import '../../../services/pos_operations_service.dart';
import '../../../utils/order_channel_utils.dart';

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

ShiftSummary _summarizeOrders(List<Order> orders, ShiftSession shift) {
  final scoped = orders.where((order) => order.shiftId == shift.id);
  var orderCount = 0;
  var voidCount = 0;
  var cashSales = 0.0;
  var knetSales = 0.0;
  var electronicSales = 0.0;
  var refundTotal = 0.0;

  for (final order in scoped) {
    if (order.status == OrderStatus.cancelled) {
      voidCount += 1;
      continue;
    }
    orderCount += 1;
    final total = order.totalPrice;
    if (isCashPaymentMethod(order.paymentMethod)) {
      cashSales += total;
    } else if (isKnetPaymentMethod(order.paymentMethod)) {
      knetSales += total;
    } else if ((order.paymentMethod ?? '').trim().isNotEmpty) {
      electronicSales += total;
    }
  }

  final expectedCash = shift.openingFloat + cashSales - refundTotal;
  return ShiftSummary(
    orderCount: orderCount,
    voidCount: voidCount,
    cashSales: cashSales,
    knetSales: knetSales,
    electronicSales: electronicSales,
    refundTotal: refundTotal,
    expectedCash: expectedCash,
    grossSales: cashSales + knetSales + electronicSales,
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
  var _loadingSummary = true;
  String? _error;
  late ShiftSession _shift;
  ShiftSummary _summary = const ShiftSummary();

  @override
  void initState() {
    super.initState();
    _shift = widget.shift;
    _summary = _summarizeOrders(const [], widget.shift);
    _refreshSummary();
  }

  @override
  void dispose() {
    _cashController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _refreshSummary() async {
    try {
      final results = await Future.wait([
        PosOperationsService.instance.fetchCurrentShift(
          cashierId: widget.shift.cashierId,
        ),
        ApiService.instance.fetchOrders(),
      ]);
      if (!mounted) return;
      final live = results[0] as ShiftSession?;
      final orders = results[1] as List<Order>;
      final shift = live ?? widget.shift;
      setState(() {
        _shift = shift;
        _summary = _summarizeOrders(orders, shift);
        _loadingSummary = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _summary = _summarizeOrders(const [], _shift);
        _loadingSummary = false;
      });
    }
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
        shiftId: _shift.id,
        closingCashCounted: counted,
        notes: _notesController.text.trim(),
        closedById: cashier?.staff.id ?? _shift.cashierId,
        closedByName: cashier?.staff.name ?? _shift.cashierName,
        cashierId: _shift.cashierId,
        cashierName: _shift.cashierName,
        openingFloat: _shift.openingFloat,
        roleId: _shift.roleId,
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
    final summary = _summary.orderCount > 0 || _summary.cashSales > 0
        ? _summary
        : ShiftSummary(
            orderCount: _shift.summary.orderCount,
            voidCount: _shift.summary.voidCount,
            cashSales: _shift.summary.cashSales,
            knetSales: _shift.summary.knetSales,
            electronicSales: _shift.summary.electronicSales,
            refundTotal: _shift.summary.refundTotal,
            expectedCash: _shift.openingFloat +
                _shift.summary.cashSales -
                _shift.summary.refundTotal,
            grossSales: _shift.summary.grossSales,
          );
    final expectedCash = _shift.openingFloat + summary.cashSales - summary.refundTotal;

    return AlertDialog(
      title: const Text('إغلاق الوردية — جرد مالي'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('الكاشير: ${_shift.cashierName}'),
              Text(
                'افتتاح الدرج: ${_shift.openingFloat.toStringAsFixed(3)} د.ك',
              ),
              const SizedBox(height: 12),
              if (_loadingSummary)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else ...[
                _summaryRow('عدد الطلبات', '${summary.orderCount}'),
                _summaryRow(
                  'مبيعات كاش',
                  '${summary.cashSales.toStringAsFixed(3)} د.ك',
                ),
                _summaryRow(
                  'مبيعات K-Net',
                  '${summary.knetSales.toStringAsFixed(3)} د.ك',
                ),
                _summaryRow(
                  'مبيعات إلكترونية',
                  '${summary.electronicSales.toStringAsFixed(3)} د.ك',
                ),
                _summaryRow(
                  'مرتجعات',
                  '${summary.refundTotal.toStringAsFixed(3)} د.ك',
                ),
                _summaryRow('إلغاءات', '${summary.voidCount}'),
                const Divider(),
                _summaryRow(
                  'النقد المتوقع',
                  '${expectedCash.toStringAsFixed(3)} د.ك',
                ),
              ],
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
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _submitting || _loadingSummary ? null : _submit,
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
