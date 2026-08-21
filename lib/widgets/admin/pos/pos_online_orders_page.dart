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
import '../../../services/pos_print_helper.dart';
import '../../../services/restaurant_settings_service.dart';
import '../../../utils/order_channel_utils.dart';
import '../admin_corner_toast.dart';
import '../admin_order_details_dialog.dart';
import '../order_status_chip.dart';
import '../../../utils/pos_receipt_html.dart';

/// Incoming online / QR menu orders for the active cashier shift.
class PosOnlineOrdersPage extends StatefulWidget {
  const PosOnlineOrdersPage({super.key});

  @override
  State<PosOnlineOrdersPage> createState() => _PosOnlineOrdersPageState();
}

class _PosOnlineOrdersPageState extends State<PosOnlineOrdersPage>
    with SingleTickerProviderStateMixin {
  static const burgundy = Color(0xFF6B1124);

  final _ordersService = OrdersService.instance;
  final _monitor = AdminOrderMonitorService.instance;
  List<SalesPlatformConfig> _platforms = SalesPlatformConfig.defaults();
  var _processingId = '';
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    unawaited(_loadPlatforms());
    unawaited(_ordersService.refreshOrders());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPlatforms() async {
    try {
      final settings = await RestaurantSettingsService.instance.load();
      if (!mounted) return;
      setState(() => _platforms = settings.resolvedSalesPlatforms);
    } catch (_) {}
  }

  bool get _canProcess =>
      PosOperationsService.instance.allows(
        PosPermissionKeys.receiveOnlineOrders,
      );

  bool _belongsToCashier(Order order) {
    final session = PosOperationsService.instance.cashierSession;
    final shift = PosOperationsService.instance.activeShift;
    final cashierId = (session?.staff.id ?? shift?.cashierId ?? '').trim();
    final shiftId = (shift?.id ?? '').trim();
    final cashierName =
        (session?.staff.name ?? shift?.cashierName ?? '').trim().toLowerCase();

    final orderCashierId = (order.cashierId ?? '').trim();
    final orderShiftId = (order.shiftId ?? '').trim();
    final orderCashierName = order.receivedByCashierLabel.trim().toLowerCase();

    if (orderCashierId.isNotEmpty &&
        cashierId.isNotEmpty &&
        orderCashierId == cashierId) {
      return true;
    }
    if (orderShiftId.isNotEmpty &&
        shiftId.isNotEmpty &&
        orderShiftId == shiftId) {
      return true;
    }
    if (orderCashierName.isNotEmpty &&
        cashierName.isNotEmpty &&
        orderCashierName == cashierName) {
      return true;
    }
    return false;
  }

  ({String cashierId, String cashierName, String shiftId}) get _receivingIdentity {
    final shift = PosOperationsService.instance.activeShift;
    final cashier = PosOperationsService.instance.cashierSession;
    final staffId = cashier?.staff.id.trim() ?? '';
    final staffName = cashier?.staff.name.trim() ?? '';
    final shiftCashierId = shift?.cashierId.trim() ?? '';
    final shiftCashierName = shift?.cashierName.trim() ?? '';
    final sessionName = AdminAuthService.instance.session?.staffName?.trim() ?? '';
    final sessionId = AdminAuthService.instance.session?.staffId?.trim() ?? '';
    final cashierId = [
      staffId,
      shiftCashierId,
      sessionId,
    ].firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final cashierName = [
      staffName,
      shiftCashierName,
      sessionName,
    ].firstWhere((value) => value.isNotEmpty, orElse: () => 'كاشير');
    return (
      cashierId: cashierId,
      cashierName: cashierName,
      shiftId: shift?.id.trim() ?? '',
    );
  }

  Future<void> _updateMineStatus(Order order, OrderStatus status) async {
    setState(() => _processingId = order.id);
    try {
      final identity = _receivingIdentity;
      await _ordersService.updateOrderStatus(
        order.id,
        status,
        shiftId: identity.shiftId.isNotEmpty ? identity.shiftId : order.shiftId,
        cashierId:
            identity.cashierId.isNotEmpty ? identity.cashierId : order.cashierId,
        cashierName: identity.cashierName.isNotEmpty
            ? identity.cashierName
            : order.cashierName,
      );
      if (!mounted) return;
      if (status == OrderStatus.delivered) {
        _tabController.animateTo(2);
        AdminCornerToast.success(context, 'تم التوصيل — الطلب انتقل للسابقة');
      } else if (status == OrderStatus.preparing) {
        AdminCornerToast.success(context, 'الطلب في الطريق');
      } else {
        AdminCornerToast.success(context, 'تم تحديث حالة الطلب');
      }
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

  Future<void> _openDetails(Order order) async {
    await showAdminOrderDetailsDialog(
      context,
      order: order,
      platforms: _platforms,
      onStatusChanged: (orderId, status) => _updateMineStatus(order, status),
    );
  }

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
      final identity = _receivingIdentity;
      await _ordersService.updateOrderStatus(
        order.id,
        OrderStatus.confirmed,
        shiftId: identity.shiftId,
        cashierId: identity.cashierId,
        cashierName: identity.cashierName,
      );

      if (!mounted) return;

      if (PosOperationsService.instance.allows(PosPermissionKeys.printInvoice)) {
        await PosPrintHelper.printIfAuto(
          order: order.copyWith(status: OrderStatus.confirmed),
          kind: PosReceiptKind.kitchen,
        );
      }

      if (!mounted) return;
      AdminCornerToast.success(context, 'تم قبول الطلب — نفّذه من تبويب الحالية');
      _tabController.animateTo(1);
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
      await _ordersService.updateOrderStatus(
        order.id,
        OrderStatus.cancelled,
      );
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
      child: ListenableBuilder(
        listenable: PosOperationsService.instance,
        builder: (context, _) {
          return StreamBuilder<List<Order>>(
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
          final currentMine = orders
              .where(
                (order) =>
                    isOnlineMenuOrder(order) &&
                    order.status.isInProgressForCashier &&
                    _belongsToCashier(order),
              )
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final previousMine = orders
              .where(
                (order) =>
                    isOnlineMenuOrder(order) &&
                    order.status == OrderStatus.delivered &&
                    _belongsToCashier(order),
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
                currentCount: currentMine.length,
                previousCount: previousMine.length,
                shiftOpen: shift?.isOpen == true,
                onlineCashBound: onlineCashBound,
                expectedCash: shift?.summary.expectedCash ?? 0,
                cashierName: PosOperationsService.instance.cashierSession?.staff.name ??
                    shift?.cashierName ??
                    '',
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
              Material(
                color: Colors.white,
                child: TabBar(
                  controller: _tabController,
                  labelColor: burgundy,
                  unselectedLabelColor: Colors.grey.shade600,
                  indicatorColor: const Color(0xFFD49A00),
                  indicatorWeight: 3,
                  tabs: [
                    Tab(text: 'جديدة (${pendingOnline.length})'),
                    Tab(text: 'حالية (${currentMine.length})'),
                    Tab(text: 'سابقة (${previousMine.length})'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _PosOnlineOrdersList(
                      orders: pendingOnline,
                      dateFormat: dateFormat,
                      platforms: _platforms,
                      processingId: _processingId,
                      emptyTitle: 'لا توجد طلبات جديدة',
                      emptySubtitle:
                          'ستظهر هنا طلبات QR / المنيو فور إرسال العميل.',
                      onAccept: _acceptOrder,
                      onReject: _rejectOrder,
                      onOpen: _openDetails,
                    ),
                    _PosOnlineOrdersList(
                      orders: currentMine,
                      dateFormat: dateFormat,
                      platforms: _platforms,
                      processingId: _processingId,
                      emptyTitle: 'لا توجد طلبات حالية في حسابك',
                      emptySubtitle:
                          'بعد القبول يظهر الطلب هنا. نفّذ «في الطريق» ثم «تم التوصيل».',
                      onOpen: _openDetails,
                      onNextStatus: _updateMineStatus,
                    ),
                    _PosOnlineOrdersList(
                      orders: previousMine,
                      dateFormat: dateFormat,
                      platforms: _platforms,
                      processingId: _processingId,
                      emptyTitle: 'لا توجد طلبات تم توصيلها',
                      emptySubtitle:
                          'الطلبات التي توصّلها لهذا الكاشير تُحفظ هنا.',
                      onOpen: _openDetails,
                      readOnly: true,
                    ),
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

class _OnlineOrdersHeader extends StatelessWidget {
  const _OnlineOrdersHeader({
    required this.pendingCount,
    required this.currentCount,
    required this.previousCount,
    required this.shiftOpen,
    required this.onlineCashBound,
    required this.expectedCash,
    required this.cashierName,
  });

  final int pendingCount;
  final int currentCount;
  final int previousCount;
  final bool shiftOpen;
  final double onlineCashBound;
  final double expectedCash;
  final String cashierName;

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'طلبات المنيو الإلكتروني',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: burgundy,
                      ),
                    ),
                    Text(
                      cashierName.isEmpty
                          ? 'طلبات الموقع للعملاء — القبول يضيف الطلب لوردية الكاشير'
                          : 'حساب الكاشير: $cashierName — كل طلب تقبله يدخل ورديتك',
                      style: const TextStyle(color: Color(0xFF666666), fontSize: 13),
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
                  icon: Icons.receipt_long_outlined,
                  label: 'حالية في حسابك',
                  value: '$currentCount',
                  color: burgundy,
                ),
                _MetricChip(
                  icon: Icons.inventory_2_outlined,
                  label: 'سابقة في حسابك',
                  value: '$previousCount',
                  color: Colors.blueGrey,
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

class _PosOnlineOrdersList extends StatelessWidget {
  const _PosOnlineOrdersList({
    required this.orders,
    required this.dateFormat,
    required this.platforms,
    required this.processingId,
    required this.emptyTitle,
    required this.emptySubtitle,
    this.onAccept,
    this.onReject,
    this.onOpen,
    this.onNextStatus,
    this.readOnly = false,
  });

  final List<Order> orders;
  final DateFormat dateFormat;
  final List<SalesPlatformConfig> platforms;
  final String processingId;
  final String emptyTitle;
  final String emptySubtitle;
  final Future<void> Function(Order order)? onAccept;
  final Future<void> Function(Order order)? onReject;
  final Future<void> Function(Order order)? onOpen;
  final Future<void> Function(Order order, OrderStatus status)? onNextStatus;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return _EmptyOnlineOrders(title: emptyTitle, subtitle: emptySubtitle);
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final order = orders[index];
        return _PosOnlineOrderCard(
          order: order,
          dateFormat: dateFormat,
          platforms: platforms,
          isProcessing: processingId == order.id,
          onAccept: onAccept == null ? null : () => onAccept!(order),
          onReject: onReject == null ? null : () => onReject!(order),
          onOpen: onOpen == null ? null : () => onOpen!(order),
          onNext: order.status.nextStatus == null || onNextStatus == null || readOnly
              ? null
              : () => onNextStatus!(order, order.status.nextStatus!),
          nextLabel: order.status.nextActionLabel,
        );
      },
    );
  }
}

class _PosOnlineOrderCard extends StatelessWidget {
  const _PosOnlineOrderCard({
    required this.order,
    required this.dateFormat,
    required this.platforms,
    required this.isProcessing,
    this.onAccept,
    this.onReject,
    this.onOpen,
    this.onNext,
    this.nextLabel,
  });

  final Order order;
  final DateFormat dateFormat;
  final List<SalesPlatformConfig> platforms;
  final bool isProcessing;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onOpen;
  final VoidCallback? onNext;
  final String? nextLabel;

  @override
  Widget build(BuildContext context) {
    final platform = PlatformCatalog.resolve(order.orderSource, platforms);
    final isCash = isCashPaymentMethod(order.paymentMethod);
    final itemSummary = order.items
        .map((item) => '${item.quantity}x ${item.name}')
        .join(' • ');

    return Card(
      elevation: order.status == OrderStatus.pending ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: order.status == OrderStatus.pending
              ? Colors.orange.shade300
              : const Color(0xFFE2E8F0),
          width: order.status == OrderStatus.pending ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
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
            if (order.receivedByCashierLabel.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'المستلم: ${order.receivedByCashierLabel}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B1124),
                ),
              ),
            ],
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
            if (onAccept != null && isCash) ...[
              const SizedBox(height: 6),
              Text(
                'سيُضاف هذا الطلب لورديتك عند القبول',
                style: TextStyle(fontSize: 12, color: Colors.green.shade700),
              ),
            ],
            if (onAccept != null && onReject != null) ...[
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
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6B1124),
                      ),
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
            ] else if (onNext != null && nextLabel != null) ...[
              const SizedBox(height: 10),
              Text(
                order.status == OrderStatus.confirmed
                    ? 'الخطوة التالية: تحويل الطلب إلى «في الطريق»'
                    : 'الخطوة التالية: تأكيد «تم التوصيل» لنقله للسابقة',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: isProcessing ? null : onNext,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  backgroundColor: order.status == OrderStatus.confirmed
                      ? Colors.orange.shade700
                      : Colors.green.shade700,
                ),
                icon: Icon(
                  order.status == OrderStatus.confirmed
                      ? Icons.delivery_dining
                      : Icons.check_circle,
                ),
                label: Text(nextLabel!),
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}

class _EmptyOnlineOrders extends StatelessWidget {
  const _EmptyOnlineOrders({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

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
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6B1124),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
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
        'تحتاج صلاحية «استلام طلبات الموقع الإلكتروني للعملاء» لقبول الطلبات.',
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
