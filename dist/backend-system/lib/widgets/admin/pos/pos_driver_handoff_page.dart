import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/order.dart';
import '../../../models/pos_role.dart';
import '../../../services/api_service.dart';
import '../../../services/delivery_dispatch_service.dart';
import '../../../services/orders_service.dart';
import '../../../services/pos_operations_service.dart';
import '../admin_corner_toast.dart';
import '../driver_handshake_banners.dart';

/// Dedicated cashier till for cash-in from the driver or paying the delivery fee.
class PosDriverHandoffPage extends StatefulWidget {
  const PosDriverHandoffPage({super.key, this.showPageHeader = true});

  final bool showPageHeader;

  @override
  State<PosDriverHandoffPage> createState() => _PosDriverHandoffPageState();
}

class _PosDriverHandoffPageState extends State<PosDriverHandoffPage> {
  static const burgundy = Color(0xFF6B1124);

  final _ordersService = OrdersService.instance;
  var _processingId = '';

  @override
  void initState() {
    super.initState();
    unawaited(_ordersService.refreshOrders());
    DeliveryBoardController.instance.ensureStarted();
  }

  bool get _canProcess => PosOperationsService.instance.allows(
        PosPermissionKeys.receiveOnlineOrders,
      );

  Order _withDispatch(Order order) {
    final req = DeliveryBoardController.instance.requestForOrder(order.id);
    if (req == null) return order;
    final mappedStatus = (req.status).trim().toLowerCase().replaceAll('-', '_');
    final deliveryStatus = mappedStatus == 'accepted' ? 'driver_accepted' : req.status;
    return order.copyWith(
      assignedDriverId: (order.assignedDriverId ?? '').trim().isNotEmpty
          ? order.assignedDriverId
          : req.assignedDriverId,
      assignedDriverName: (order.assignedDriverName ?? '').trim().isNotEmpty
          ? order.assignedDriverName
          : req.assignedDriverName,
      assignedDriverPhone: (order.assignedDriverPhone ?? '').trim().isNotEmpty
          ? order.assignedDriverPhone
          : req.assignedDriverPhone,
      deliveryStatus: (order.deliveryStatus ?? '').trim().isNotEmpty
          ? order.deliveryStatus
          : deliveryStatus,
      deliveryRequestId: (order.deliveryRequestId ?? '').trim().isNotEmpty
          ? order.deliveryRequestId
          : req.id,
      driverFee: order.driverFee ?? req.handshakeDriverFee ?? req.driverFee,
      cashierHandoffConfirmedAt:
          order.cashierHandoffConfirmedAt ?? req.cashierHandoffConfirmedAt,
      driverHandoffConfirmedAt:
          order.driverHandoffConfirmedAt ?? req.driverHandoffConfirmedAt,
      handshakeNetToCashier:
          order.handshakeNetToCashier ?? req.handshakeNetToCashier,
      handshakeCashierPaysDriver:
          order.handshakeCashierPaysDriver ?? req.handshakeCashierPaysDriver,
      handshakeCollectFromCustomer:
          order.handshakeCollectFromCustomer ?? req.handshakeCollectFromCustomer,
    );
  }

  Future<void> _confirmHandoff(Order order) async {
    final requestId = (order.deliveryRequestId ?? '').trim().isNotEmpty
        ? order.deliveryRequestId!.trim()
        : (DeliveryBoardController.instance.requestForOrder(order.id)?.id ?? '');
    if (requestId.isEmpty) {
      AdminCornerToast.error(context, 'لا يوجد طلب توصيل مرتبط');
      return;
    }
    setState(() => _processingId = order.id);
    try {
      await ApiService.instance.postDeliveryAction(requestId, 'cashier-confirm');
      await _ordersService.refreshOrders();
      if (!mounted) return;
      final money = HandshakeMoney.fromOrder(order);
      AdminCornerToast.success(
        context,
        money.isCash
            ? 'تم تسجيل استلام النقدية من السائق'
            : 'تم تسجيل دفع رسوم التوصيل للسائق',
      );
    } catch (error) {
      if (!mounted) return;
      AdminCornerToast.error(
        context,
        error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _processingId = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF4F6F8),
      child: ListenableBuilder(
        listenable: Listenable.merge([
          PosOperationsService.instance,
          DeliveryBoardController.instance,
        ]),
        builder: (context, _) {
          return StreamBuilder<List<Order>>(
            stream: _ordersService.watchOrders(),
            initialData: const [],
            builder: (context, snapshot) {
              final orders = (snapshot.data ?? []).map(_withDispatch).toList();
              final awaitingCashier = orders
                  .where((order) => order.needsCashierHandoff)
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
              final waitingDriver = orders
                  .where((order) => order.waitingDriverAfterCashierConfirm)
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.showPageHeader)
                    Material(
                      color: burgundy,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'صندوق السائق',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'استلم نقدية الطلب من السائق، أو ادفع له رسوم التوصيل، ثم أكّد حتى يستلم الطلب.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (!_canProcess)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'لا تملك صلاحية استلام طلبات التوصيل.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: [
                        if (awaitingCashier.isEmpty && waitingDriver.isEmpty)
                          const _EmptyHandoffState(),
                        if (awaitingCashier.isNotEmpty) ...[
                          Text(
                            'يحتاج تأكيدك الآن (${awaitingCashier.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...awaitingCashier.map(
                            (order) => _HandoffTillCard(
                              order: order,
                              processing: _processingId == order.id,
                              canProcess: _canProcess,
                              onConfirm: () => _confirmHandoff(order),
                            ),
                          ),
                        ],
                        if (waitingDriver.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'بانتظار تأكيد السائق (${waitingDriver.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...waitingDriver.map(
                            (order) => _HandoffTillCard(
                              order: order,
                              processing: false,
                              canProcess: false,
                              onConfirm: null,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyHandoffState extends StatelessWidget {
  const _EmptyHandoffState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Icon(Icons.storefront_outlined, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            'لا يوجد سائق عند الصندوق الآن',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            'عندما يقبل سائق طلباً ويأتي لاستلامه، تظهر هنا عملية استلام النقدية أو دفع رسوم التوصيل.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _HandoffTillCard extends StatelessWidget {
  const _HandoffTillCard({
    required this.order,
    required this.processing,
    required this.canProcess,
    required this.onConfirm,
  });

  final Order order;
  final bool processing;
  final bool canProcess;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final money = HandshakeMoney.fromOrder(order);
    final driverName = (order.assignedDriverName ?? '').trim();
    final invoice = (order.invoiceNumber ?? '').trim();
    final cashIn = money.isCash;
    final amount = cashIn ? money.netToCashier : money.cashierPaysDriver;
    final amountColor = cashIn ? const Color(0xFF1B5E20) : const Color(0xFFBF360C);
    final cardColor = cashIn ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: amountColor.withValues(alpha: 0.28), width: 1.4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: amountColor.withValues(alpha: 0.12),
                  child: Icon(
                    cashIn ? Icons.call_received : Icons.call_made,
                    color: amountColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driverName.isEmpty ? 'سائق' : driverName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        [
                          if (invoice.isNotEmpty) 'فاتورة $invoice',
                          'طلب ${order.id}',
                        ].join(' • '),
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    cashIn ? 'كاش — استلم من السائق' : 'كينت/أونلاين — ادفع للسائق',
                    style: TextStyle(
                      color: amountColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Text(
                    cashIn
                        ? 'استلم من السائق صافي الطعام'
                        : 'ادفع رسوم التوصيل للسائق',
                    style: TextStyle(
                      color: amountColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${amount.toStringAsFixed(3)} د.ك',
                    style: TextStyle(
                      color: amountColor,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    cashIn
                        ? 'إجمالي الطلب ${money.orderTotal.toStringAsFixed(3)} − رسوم السائق ${money.driverFee.toStringAsFixed(3)}'
                        : 'الطلب مدفوع مسبقاً — لا تستلم مبلغاً من السائق. رسوم المنطقة ${money.driverFee.toStringAsFixed(3)} د.ك',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: amountColor.withValues(alpha: 0.9),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (order.waitingDriverAfterCashierConfirm)
              const HandshakeBanner(
                tone: HandshakeTone.wait,
                text: 'تم تأكيدك — بانتظار تأكيد السائق لاستلام الطلب',
              )
            else if (canProcess && onConfirm != null)
              FilledButton(
                onPressed: processing ? null : onConfirm,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6B1124),
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: processing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        cashIn
                            ? 'استلمت النقدية من السائق — تأكيد'
                            : 'دفعت رسوم التوصيل للسائق — تأكيد',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
