import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/order.dart';
import '../../../models/pos_role.dart';
import '../../../models/sales_platform_config.dart';
import '../../../services/admin_auth_service.dart';
import '../../../services/admin_order_monitor_service.dart';
import '../../../services/orders_service.dart';
import '../../../services/pos_operations_service.dart';
import '../../../services/restaurant_settings_service.dart';
import '../../../utils/order_channel_utils.dart';
import '../admin_corner_toast.dart';
import '../order_status_chip.dart';
import 'pos_print_preview_dialog.dart';
import '../../../utils/pos_receipt_html.dart';

/// Incoming online / QR menu orders for the active cashier shift.
class PosOnlineOrdersPage extends StatefulWidget {
  const PosOnlineOrdersPage({super.key});

  @override
  State<PosOnlineOrdersPage> createState() => _PosOnlineOrdersPageState();
}

class _PosOnlineOrdersPageState extends State<PosOnlineOrdersPage> {
  static const burgundy = Color(0xFF6B1124);

  final _ordersService = OrdersService.instance;
  final _monitor = AdminOrderMonitorService.instance;
  List<SalesPlatformConfig> _platforms = SalesPlatformConfig.defaults();
  var _processingId = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadPlatforms());
    unawaited(_ordersService.refreshOrders());
  }

  Future<void> _loadPlatforms() async {
    try {
      final settings = await RestaurantSettingsService.instance.load();
      if (!mounted) return;
      setState(() => _platforms = settings.resolvedSalesPlatforms);
    } catch (_) {}
  }

  bool get _canProcess =>
      PosOperationsService.instance.allows(PosPermissionKeys.processOrders);

  Future<void> _acceptOrder(Order order) async {
    if (!_canProcess) {
      AdminCornerToast.error(context, 'لا تملك صلاحية معالجة الطلبات');
      return;
    }

    final activeShift = PosOperationsService.instance.activeShift;
    if (activeShift == null || !activeShift.isOpen) {
      AdminCornerToast.error(context, 'افتح وردية POS قبل قبول طلبات المنيو');
      return;
    }

    setState(() => _processingId = order.id);
    await _monitor.acknowledgeOrder(order.id);

    try {
      final cashier = PosOperationsService.instance.cashierSession;
      await _ordersService.updateOrderStatus(
        order.id,
        OrderStatus.confirmed,
        shiftId: activeShift.id,
        cashierId: cashier?.staff.id,
      );
      await PosOperationsService.instance.fetchCurrentShift(
        cashierId: cashier?.staff.id,
      );

      if (!mounted) return;

      if (PosOperationsService.instance.allows(PosPermissionKeys.printInvoice)) {
        await showPosPrintPreviewDialog(
          context,
          order: order.copyWith(status: OrderStatus.confirmed),
          restaurantName:
              AdminAuthService.instance.restaurantName ?? 'المطعم',
          platforms: _platforms,
          kind: PosReceiptKind.kitchen,
        );
      }

      if (!mounted) return;
      AdminCornerToast.success(context, 'تم قبول الطلب وإرساله للمطبخ');
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

  Future<void> _rejectOrder(Order order) async {
    if (!_canProcess) {
      AdminCornerToast.error(context, 'لا تملك صلاحية معالجة الطلبات');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('رفض الطلب'),
        content: Text(
          'هل تريد رفض طلب ${order.customerName} '
          '(${order.totalPrice.toStringAsFixed(3)} د.ك)؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('رفض'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _processingId = order.id);
    await _monitor.acknowledgeOrder(order.id);

    try {
      final activeShift = PosOperationsService.instance.activeShift;
      final cashier = PosOperationsService.instance.cashierSession;
      await _ordersService.updateOrderStatus(
        order.id,
        OrderStatus.cancelled,
        shiftId: activeShift?.id,
        cashierId: cashier?.staff.id,
      );
      if (activeShift != null) {
        await PosOperationsService.instance.fetchCurrentShift(
          cashierId: cashier?.staff.id,
        );
      }
      if (!mounted) return;
      AdminCornerToast.success(context, 'تم رفض الطلب');
    } catch (error) {
      if (!mounted) return;
      AdminCornerToast.error(context, 'تعذر رفض الطلب');
    } finally {
      if (mounted) setState(() => _processingId = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d/M • HH:mm');

    return ColoredBox(
      color: const Color(0xFFF4F6F8),
      child: StreamBuilder<List<Order>>(
        stream: _ordersService.watchOrders(),
        initialData: const [],
        builder: (context, snapshot) {
          final orders = snapshot.data ?? [];
          final pendingOnline = orders
              .where(
                (order) =>
                    order.status == OrderStatus.pending &&
                    isOnlineMenuOrder(order),
              )
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          final shift = PosOperationsService.instance.activeShift;
          final onlineCashBound = shift?.cashCollected ?? 0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OnlineOrdersHeader(
                pendingCount: pendingOnline.length,
                shiftOpen: shift?.isOpen == true,
                onlineCashBound: onlineCashBound,
                expectedCash: shift?.summary.expectedCash ?? 0,
              ),
              if (!_canProcess)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: _PermissionBanner(),
                ),
              if (shift == null || !shift.isOpen)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: _ShiftRequiredBanner(),
                ),
              Expanded(
                child: pendingOnline.isEmpty
                    ? const _EmptyOnlineOrders()
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: pendingOnline.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final order = pendingOnline[index];
                          return _PosOnlineOrderCard(
                            order: order,
                            dateFormat: dateFormat,
                            platforms: _platforms,
                            isProcessing: _processingId == order.id,
                            onAccept: () => _acceptOrder(order),
                            onReject: () => _rejectOrder(order),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OnlineOrdersHeader extends StatelessWidget {
  const _OnlineOrdersHeader({
    required this.pendingCount,
    required this.shiftOpen,
    required this.onlineCashBound,
    required this.expectedCash,
  });

  final int pendingCount;
  final bool shiftOpen;
  final double onlineCashBound;
  final double expectedCash;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: burgundy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.qr_code_scanner, color: burgundy),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'طلبات المنيو الإلكتروني',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: burgundy,
                      ),
                    ),
                    Text(
                      'طلبات QR / المنيو أونلاين — قبول أو رفض',
                      style: TextStyle(color: Color(0xFF666666), fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (pendingCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Text(
                    '$pendingCount جديد',
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          if (shiftOpen) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip(
                  icon: Icons.payments_outlined,
                  label: 'كاش أونلاين محصّل',
                  value: '${onlineCashBound.toStringAsFixed(3)} د.ك',
                  color: Colors.green.shade700,
                ),
                _MetricChip(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'كاش متوقع بالدرج',
                  value: '${expectedCash.toStringAsFixed(3)} د.ك',
                  color: burgundy,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static const burgundy = Color(0xFF6B1124);
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text('$label: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          Text(
            value,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

class _PosOnlineOrderCard extends StatelessWidget {
  const _PosOnlineOrderCard({
    required this.order,
    required this.dateFormat,
    required this.platforms,
    required this.isProcessing,
    required this.onAccept,
    required this.onReject,
  });

  final Order order;
  final DateFormat dateFormat;
  final List<SalesPlatformConfig> platforms;
  final bool isProcessing;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final platform = PlatformCatalog.resolve(order.orderSource, platforms);
    final isCash = isCashPaymentMethod(order.paymentMethod);
    final itemSummary = order.items
        .map((item) => '${item.quantity}x ${item.name}')
        .join(' • ');

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.orange.shade300, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.customerName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '#${order.invoiceNumber ?? order.id.substring(0, 8)}',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                OrderStatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: 8),
            SalesPlatformBadge(platform: platform),
            const SizedBox(height: 10),
            Text('📞 ${order.phone}', style: const TextStyle(fontSize: 13)),
            if (order.address.trim().isNotEmpty)
              Text('📍 ${order.address}', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Text(itemSummary, style: TextStyle(color: Colors.grey.shade800)),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '${order.totalPrice.toStringAsFixed(3)} د.ك',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6B1124),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isCash ? Colors.green.shade50 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    order.paymentMethod ?? '—',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isCash ? Colors.green.shade800 : Colors.blue.shade800,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  dateFormat.format(order.createdAt.toLocal()),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
            if (isCash) ...[
              const SizedBox(height: 6),
              Text(
                'سيُضاف للوردية النشطة تلقائياً عند القبول',
                style: TextStyle(fontSize: 12, color: Colors.green.shade700),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isProcessing ? null : onReject,
                    icon: const Icon(Icons.close, color: Colors.red),
                    label: const Text('رفض', style: TextStyle(color: Colors.red)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: isProcessing ? null : onAccept,
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6B1124)),
                    icon: isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: const Text('قبول → مطبخ'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyOnlineOrders extends StatelessWidget {
  const _EmptyOnlineOrders();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_2, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'لا توجد طلبات منيو إلكترونية',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6B1124),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'ستظهر هنا الطلبات الواردة من QR / المنيو أونلاين فور إرسال العميل.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: const Text(
        'تحتاج صلاحية «معالجة الطلبات» لقبول أو رفض طلبات المنيو.',
        style: TextStyle(fontSize: 13),
      ),
    );
  }
}

class _ShiftRequiredBanner extends StatelessWidget {
  const _ShiftRequiredBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: const Text(
        'يجب فتح وردية POS قبل قبول الطلبات — لربط المبالغ النقدية بالعهدة.',
        style: TextStyle(fontSize: 13, color: Color(0xFFB71C1C)),
      ),
    );
  }
}
