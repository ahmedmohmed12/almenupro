import 'package:flutter/material.dart';

import '../../../models/delivery_dispatch.dart';
import '../../../models/order.dart';
import '../../../models/shift_session.dart';
import '../../../services/api_service.dart';
import '../../../services/pos_operations_service.dart';
import '../../../utils/order_channel_utils.dart';
import '../../../utils/order_payment_utils.dart';
import '../../../utils/pos_pending_orders.dart';

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

ShiftSummary _summarizeOrders(
  List<Order> orders,
  ShiftSession shift, [
  List<DeliveryDispatchRequest> requests = const [],
]) {
  final byOrderId = <String, DeliveryDispatchRequest>{
    for (final request in requests)
      if ((request.orderId ?? '').trim().isNotEmpty) request.orderId!.trim(): request,
  };
  final scoped = orders.where((order) => order.shiftId == shift.id);
  var orderCount = 0;
  var voidCount = 0;
  var cashSales = 0.0;
  var knetSales = 0.0;
  var electronicSales = 0.0;
  var refundTotal = 0.0;
  var deliveryExpenses = 0.0;
  var dineInSales = 0.0;
  var dineInCount = 0;
  var takeawaySales = 0.0;
  var takeawayCount = 0;
  var deliverySales = 0.0;
  var deliveryCount = 0;
  var websiteSales = 0.0;
  var websiteCount = 0;
  var posSales = 0.0;
  var posCount = 0;

  for (final order in scoped) {
    if (order.status == OrderStatus.cancelled) {
      voidCount += 1;
      continue;
    }
    if (!countsTowardShiftRevenue(order)) {
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

    if (isHallTableOrder(order)) {
      dineInSales += total;
      dineInCount += 1;
    } else if (isOnlineMenuOrder(order)) {
      websiteSales += total;
      websiteCount += 1;
    } else if (order.createdFromPos || isPosOrderSource(order.orderSource)) {
      switch (order.orderType) {
        case OrderType.pickup:
          takeawaySales += total;
          takeawayCount += 1;
        case OrderType.delivery:
        case OrderType.scheduledDelivery:
          deliverySales += total;
          deliveryCount += 1;
        case OrderType.dineIn:
          posSales += total;
          posCount += 1;
      }
    } else {
      switch (order.orderType) {
        case OrderType.dineIn:
          dineInSales += total;
          dineInCount += 1;
        case OrderType.pickup:
          takeawaySales += total;
          takeawayCount += 1;
        case OrderType.delivery:
        case OrderType.scheduledDelivery:
          deliverySales += total;
          deliveryCount += 1;
      }
    }

    final request = byOrderId[order.id];
    final assigned = (order.assignedDriverId ?? request?.assignedDriverId ?? '').trim();
    final delivered = order.status == OrderStatus.delivered ||
        (order.deliveryStatus ?? '').toLowerCase() == 'delivered' ||
        request?.status == 'delivered';
    if (assigned.isNotEmpty && delivered) {
      final fee = order.driverFee ?? request?.driverFee ?? 0;
      if (fee > 0) deliveryExpenses += fee;
    }
  }

  final expectedCash =
      shift.openingFloat + cashSales - refundTotal - deliveryExpenses;
  return ShiftSummary(
    orderCount: orderCount,
    voidCount: voidCount,
    cashSales: cashSales,
    knetSales: knetSales,
    electronicSales: electronicSales,
    refundTotal: refundTotal,
    deliveryExpenses: deliveryExpenses,
    expectedCash: expectedCash,
    grossSales: cashSales + knetSales + electronicSales,
    dineInSales: dineInSales,
    dineInCount: dineInCount,
    takeawaySales: takeawaySales,
    takeawayCount: takeawayCount,
    deliverySales: deliverySales,
    deliveryCount: deliveryCount,
    websiteSales: websiteSales,
    websiteCount: websiteCount,
    posSales: posSales,
    posCount: posCount,
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
  final _pendingReasonController = TextEditingController();
  final _supervisorPinController = TextEditingController();
  var _submitting = false;
  var _loadingSummary = true;
  String? _error;
  late ShiftSession _shift;
  ShiftSummary _summary = const ShiftSummary();
  ShiftPendingSnapshot _pending = const ShiftPendingSnapshot(
    total: 0,
    pickup: 0,
    dineIn: 0,
    online: 0,
    orders: [],
  );

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
    _pendingReasonController.dispose();
    _supervisorPinController.dispose();
    super.dispose();
  }

  Future<void> _refreshSummary() async {
    try {
      final liveFuture = PosOperationsService.instance.fetchCurrentShift(
        cashierId: widget.shift.cashierId,
      );
      final ordersFuture = ApiService.instance.fetchOrders();
      final requestsFuture = ApiService.instance.fetchDeliveryRequests().catchError(
        (_) => <DeliveryDispatchRequest>[],
      );
      final results = await Future.wait([liveFuture, ordersFuture, requestsFuture]);
      if (!mounted) return;
      final live = results[0] as ShiftSession?;
      final orders = results[1] as List<Order>;
      final requests = results[2] as List<DeliveryDispatchRequest>;
      final shift = live ?? widget.shift;
      setState(() {
        _shift = shift;
        // Prefer server live summary (includes channel breakdown).
        _summary = live?.summary ?? _summarizeOrders(orders, shift, requests);
        _pending = pendingOrdersForShift(orders, shift.id);
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

    final cashier = PosOperationsService.instance.cashierSession;
    final roleId = cashier?.staff.roleId ?? _shift.roleId;
  if (_pending.hasPending) {
      final reason = _pendingReasonController.text.trim().isNotEmpty
          ? _pendingReasonController.text.trim()
          : _notesController.text.trim();
      if (reason.length < 3) {
        setState(
          () => _error =
              'أدخل سبب إغلاق الوردية (يوجد طلبات معلّقة)',
        );
        return;
      }
      if (shiftCloseGuardCashierOnly(roleId)) {
        final pin = _supervisorPinController.text.trim();
        if (pin.length < 4) {
          setState(
            () => _error = 'أدخل PIN مشرف وردية أو مدير POS',
          );
          return;
        }
      }
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final pendingReason = _pending.hasPending
          ? (_pendingReasonController.text.trim().isNotEmpty
              ? _pendingReasonController.text.trim()
              : _notesController.text.trim())
          : null;
      final closed = await PosOperationsService.instance.closeShift(
        shiftId: _shift.id,
        closingCashCounted: counted,
        notes: _notesController.text.trim(),
        closedById: cashier?.staff.id ?? _shift.cashierId,
        closedByName: cashier?.staff.name ?? _shift.cashierName,
        cashierId: _shift.cashierId,
        cashierName: _shift.cashierName,
        openingFloat: _shift.openingFloat,
        roleId: roleId,
        managerPin: _pending.hasPending && shiftCloseGuardCashierOnly(roleId)
            ? _supervisorPinController.text.trim()
            : null,
        pendingCloseReason: pendingReason,
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
    final summary = _summary.orderCount > 0 ||
            _summary.cashSales > 0 ||
            _summary.deliveryExpenses > 0
        ? _summary
        : ShiftSummary(
            orderCount: _shift.summary.orderCount,
            voidCount: _shift.summary.voidCount,
            cashSales: _shift.summary.cashSales,
            knetSales: _shift.summary.knetSales,
            electronicSales: _shift.summary.electronicSales,
            refundTotal: _shift.summary.refundTotal,
            deliveryExpenses: _shift.summary.deliveryExpenses,
            expectedCash: _shift.openingFloat +
                _shift.summary.cashSales -
                _shift.summary.refundTotal -
                _shift.summary.deliveryExpenses,
            grossSales: _shift.summary.grossSales,
          );
    final expectedCash = _shift.openingFloat +
        summary.cashSales -
        summary.refundTotal -
        summary.deliveryExpenses;
    final roleId =
        PosOperationsService.instance.cashierSession?.staff.roleId ??
        _shift.roleId;
    final cashierOnly =
        _pending.hasPending && shiftCloseGuardCashierOnly(roleId);
    final supervisorBypass =
        _pending.hasPending && shiftCloseGuardRoleCanBypass(roleId);

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
                const SizedBox(height: 4),
                const Text(
                  'القنوات',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                shiftSummaryChannelRows(summary),
                _summaryRow(
                  'مرتجعات',
                  '${summary.refundTotal.toStringAsFixed(3)} د.ك',
                ),
                _summaryRow('إلغاءات', '${summary.voidCount}'),
                _summaryRow(
                  'مصاريف التوصيل (أجرة السائق)',
                  '- ${summary.deliveryExpenses.toStringAsFixed(3)} د.ك',
                ),
                const Divider(),
                _summaryRow(
                  'النقد المتوقع',
                  '${expectedCash.toStringAsFixed(3)} د.ك',
                ),
              ],
              if (!_loadingSummary && _pending.hasPending) ...[
                const SizedBox(height: 12),
                Material(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'طلبات معلّقة على هذه الوردية',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'الإجمالي: ${_pending.total} — استلام: ${_pending.pickup} — طاولات: ${_pending.dineIn} — موقع: ${_pending.online}',
                        ),
                        const SizedBox(height: 8),
                        for (final order in _pending.orders.take(5))
                          Text(
                            '• #${order.invoiceNumber ?? order.id} — ${order.customerName}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        if (_pending.orders.length > 5)
                          Text(
                            '… و${_pending.orders.length - 5} أخرى',
                            style: const TextStyle(fontSize: 12),
                          ),
                        if (cashierOnly)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'الكاشير: PIN مشرف/مدير + سبب الإغلاق مطلوبان.',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (cashierOnly) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _supervisorPinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'PIN مشرف وردية / مدير POS',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _pendingReasonController,
                  minLines: 2,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: cashierOnly || supervisorBypass
                        ? 'سبب الإغلاق (مطلوب)'
                        : 'سبب الإغلاق',
                    border: const OutlineInputBorder(),
                  ),
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
  final expectedCash = shift.isOpen
      ? shift.openingFloat +
          summary.cashSales -
          summary.refundTotal -
          summary.deliveryExpenses
      : summary.expectedCash;

  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(shift.isOpen ? 'ملخص الوردية الحالية' : 'ملخص الوردية'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('الكاشير: ${shift.cashierName}'),
              Text(
                'افتتاح الدرج: ${shift.openingFloat.toStringAsFixed(3)} د.ك',
              ),
              if (shift.closedAt != null)
                Text(
                  'أُغلقت: ${shift.closedAt!.toLocal().toString().substring(0, 16)}',
                ),
              const SizedBox(height: 8),
              const Text(
                'طرق الدفع',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              shiftSummaryPaymentRows(summary, openingFloat: shift.openingFloat),
              const SizedBox(height: 8),
              const Text(
                'القنوات',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              shiftSummaryChannelRows(summary),
              const Divider(),
              _summaryRow(
                shift.isOpen ? 'النقد المتوقع بالدرج' : 'النقد المتوقع',
                '${expectedCash.toStringAsFixed(3)} د.ك',
              ),
              if (!shift.isOpen) ...[
                _summaryRow(
                  'النقد الفعلي',
                  '${summary.actualCash.toStringAsFixed(3)} د.ك',
                ),
                _summaryRow(
                  'الفرق (${summary.discrepancyLabelAr})',
                  '${summary.discrepancy.toStringAsFixed(3)} د.ك',
                ),
              ],
            ],
          ),
        ),
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

Widget shiftSummaryPaymentRows(
  ShiftSummary summary, {
  double openingFloat = 0,
}) {
  return Column(
    children: [
      _summaryRow('عدد الطلبات', '${summary.orderCount}'),
      _summaryRow('مبيعات كاش', '${summary.cashSales.toStringAsFixed(3)} د.ك'),
      _summaryRow('مبيعات K-Net', '${summary.knetSales.toStringAsFixed(3)} د.ك'),
      if (summary.electronicSales > 0)
        _summaryRow(
          'مبيعات إلكترونية',
          '${summary.electronicSales.toStringAsFixed(3)} د.ك',
        ),
      _summaryRow(
        'إجمالي المبيعات',
        '${summary.grossSales.toStringAsFixed(3)} د.ك',
      ),
      _summaryRow('مرتجعات', '${summary.refundTotal.toStringAsFixed(3)} د.ك'),
      _summaryRow('إلغاءات', '${summary.voidCount}'),
      _summaryRow(
        'مصاريف التوصيل (أجرة السائق)',
        '- ${summary.deliveryExpenses.toStringAsFixed(3)} د.ك',
      ),
      if (openingFloat > 0)
        _summaryRow(
          'افتتاح الدرج',
          '${openingFloat.toStringAsFixed(3)} د.ك',
        ),
    ],
  );
}

Widget shiftSummaryChannelRows(ShiftSummary summary) {
  return Column(
    children: [
      _summaryRow(
        'طاولات / صالة',
        '${summary.dineInCount} طلب — ${summary.dineInSales.toStringAsFixed(3)} د.ك',
      ),
      _summaryRow(
        'سفري / استلام',
        '${summary.takeawayCount} طلب — ${summary.takeawaySales.toStringAsFixed(3)} د.ك',
      ),
      _summaryRow(
        'موقع العملاء',
        '${summary.websiteCount} طلب — ${summary.websiteSales.toStringAsFixed(3)} د.ك',
      ),
      _summaryRow(
        'توصيل',
        '${summary.deliveryCount} طلب — ${summary.deliverySales.toStringAsFixed(3)} د.ك',
      ),
      if (summary.posCount > 0)
        _summaryRow(
          'كاشير POS',
          '${summary.posCount} طلب — ${summary.posSales.toStringAsFixed(3)} د.ك',
        ),
    ],
  );
}

Widget _summaryRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
}
