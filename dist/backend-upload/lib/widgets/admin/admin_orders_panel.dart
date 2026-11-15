import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_strings.dart';
import '../../models/order.dart';
import '../../models/sales_platform_config.dart';
import '../../services/admin_order_focus_service.dart';
import '../../services/admin_auth_service.dart';
import '../../services/orders_service.dart';
import '../../services/incoming_order_auto_accept_service.dart';
import '../../services/delivery_dispatch_service.dart';
import '../../services/restaurant_settings_service.dart';
import '../../utils/admin_deep_link.dart';
import '../../utils/order_channel_utils.dart';
import '../../utils/order_sound.dart';
import 'admin_order_details_dialog.dart';
import 'incoming_order_countdown_badge.dart';
import 'order_status_chip.dart';
import 'order_driver_tracking_card.dart';
import 'send_rating_reminder_sheet.dart';

class AdminOrdersPanel extends StatefulWidget {
  const AdminOrdersPanel({super.key, this.onPendingCountChanged});

  final ValueChanged<int>? onPendingCountChanged;

  @override
  State<AdminOrdersPanel> createState() => AdminOrdersPanelState();
}

class AdminOrdersPanelState extends State<AdminOrdersPanel>
    with SingleTickerProviderStateMixin {
  final _ordersService = OrdersService.instance;
  final Set<String> _knownOrderIds = {};
  var _initialized = false;
  var _tableManagementEnabled = false;

  late TabController _tabController;
  var _openingFocusedOrder = false;
  String? _openedFocusRef;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    AdminOrderFocusService.instance.addListener(_onOrderFocusChanged);
    DeliveryBoardController.instance.ensureStarted();
    unawaited(_loadTableSetting());
  }

  Future<void> _loadTableSetting() async {
    try {
      final settings = await RestaurantSettingsService.instance.load();
      if (!mounted) return;
      final enabled = settings.tableManagementEnabled;
      if (enabled == _tableManagementEnabled) return;
      final index = _tabController.index;
      _tabController.dispose();
      setState(() {
        _tableManagementEnabled = enabled;
        _tabController = TabController(
          length: enabled ? 4 : 3,
          vsync: this,
          initialIndex: index.clamp(0, (enabled ? 4 : 3) - 1),
        );
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    AdminOrderFocusService.instance.removeListener(_onOrderFocusChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onOrderFocusChanged() {
    // Orders stream callback supplies the list; this just schedules a retry.
    if (!mounted) return;
    setState(() {});
  }

  void _tryOpenFocusedOrder(List<Order> orders) {
    if (!mounted || _openingFocusedOrder || orders.isEmpty) return;
    final ref = AdminOrderFocusService.instance.pendingOrderRef;
    if (ref == null || ref.isEmpty) return;
    if (_openedFocusRef == ref) return;

    Order? match;
    for (final order in orders) {
      if (AdminDeepLink.matchesOrder(
        ref,
        id: order.id,
        invoiceNumber: order.invoiceNumber,
      )) {
        match = order;
        break;
      }
    }
    if (match == null) return;

    _openedFocusRef = ref;
    AdminOrderFocusService.instance.consumeOrder();
    IncomingOrderAutoAcceptService.instance.focusDeepLinkedOrder(match);
    if (match.isNewForAdmin || match.status == OrderStatus.pending) {
      _tabController.animateTo(0);
    } else if (match.isCurrentForAdmin) {
      _tabController.animateTo(1);
    } else if (_tableManagementEnabled && isClosedHallTableOrder(match)) {
      _tabController.animateTo(3);
    } else {
      _tabController.animateTo(2);
    }
    _openingFocusedOrder = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _openingFocusedOrder = false;
        return;
      }
      try {
        await _openOrderDialog(match!);
      } finally {
        _openingFocusedOrder = false;
      }
    });
  }

  Future<void> _openOrderDialog(Order order) async {
    var platforms = SalesPlatformConfig.defaults();
    try {
      final settings = await RestaurantSettingsService.instance.load();
      platforms = settings.resolvedSalesPlatforms;
    } catch (_) {}
    if (!mounted) return;
    await showAdminOrderDetailsDialog(
      context,
      order: order,
      platforms: platforms,
      showStatusActions:
          AdminAuthService.instance.isSuperAdmin || !order.isHeldByDriver,
      onStatusChanged: (orderId, status) => _handleStatus(order, status),
    );
  }

  void selectNewOrdersTab() {
    _tabController.animateTo(0);
  }

  Future<void> _updateStatus(String orderId, OrderStatus status) async {
    final s = AppStrings.read(context);
    try {
      await _ordersService.updateOrderStatus(orderId, status);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${s.tr('تم تحديث الحالة', 'Status updated')}: ${status.arabicLabel}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${s.tr('تعذر تحديث الطلب', 'Could not update order')}: $error',
          ),
        ),
      );
    }
  }

  Future<void> _handleStatus(Order order, OrderStatus status) async {
    if (order.isHeldByDriver && !AdminAuthService.instance.isSuperAdmin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(Order.driverCustodyLockMessage)),
      );
      return;
    }
    if (order.status == OrderStatus.pending &&
        status == OrderStatus.confirmed) {
      try {
        await IncomingOrderAutoAcceptService.instance.acceptManually(order);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تحديث الحالة: ${status.arabicLabel}')),
        );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر تحديث الطلب: $error')));
      }
      return;
    }
    await _updateStatus(order.id, status);
  }

  void _handleOrdersUpdate(List<Order> orders) {
    final pendingCount = orders.where(isPendingOnlineMenuOrder).length;
    widget.onPendingCountChanged?.call(pendingCount);

    if (!_initialized) {
      _knownOrderIds
        ..clear()
        ..addAll(orders.map((order) => order.id));
      _initialized = true;
      return;
    }

    for (final order in orders) {
      if (!isPendingOnlineMenuOrder(order)) continue;
      if (_knownOrderIds.contains(order.id)) continue;

      _knownOrderIds.add(order.id);
      playNewOrderSound();

      if (!mounted) continue;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 4),
          content: Text(
            '🔔 طلب جديد #${order.invoiceNumber ?? order.id.substring(0, 6)} '
            'من ${order.customerName}',
          ),
        ),
      );
    }

    _knownOrderIds
      ..clear()
      ..addAll(orders.map((order) => order.id));
  }

  List<Order> _newOrders(List<Order> orders) {
    final list = orders.where((order) => order.isNewForAdmin).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  List<Order> _currentOrders(List<Order> orders) {
    final list = orders.where((order) => order.isCurrentForAdmin).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  List<Order> _archivedOrders(List<Order> orders) {
    final archived =
        orders
            .where(
              (order) =>
                  order.status.isArchivedForAdmin &&
                  !(_tableManagementEnabled && isClosedHallTableOrder(order)),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return archived;
  }

  List<Order> _hallTableOrders(List<Order> orders) {
    final list = orders.where(isClosedHallTableOrder).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final dateFormat = DateFormat('d/M • HH:mm');

    return StreamBuilder<List<Order>>(
      stream: _ordersService.watchOrders(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF6B1124)),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '${s.tr('خطأ في تحميل الطلبات', 'Error loading orders')}: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final orders = snapshot.data ?? [];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleOrdersUpdate(orders);
          _tryOpenFocusedOrder(orders);
        });

        final newOrders = _newOrders(orders);
        final currentOrders = _currentOrders(orders);
        final archivedOrders = _archivedOrders(orders);
        final hallOrders = _tableManagementEnabled
            ? _hallTableOrders(orders)
            : const <Order>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OrdersPageHeader(
              newCount: newOrders.length,
              currentCount: currentOrders.length,
              archivedCount: archivedOrders.length,
              hallCount: hallOrders.length,
              tableManagementEnabled: _tableManagementEnabled,
              pendingCount: orders.where(isPendingOnlineMenuOrder).length,
            ),
            if (_ordersService.isDemoMode) const _DemoOrdersBanner(),
            Material(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: const Color(0xFF6B1124),
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: const Color(0xFFD49A00),
                indicatorWeight: 3,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.fiber_new_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '${s.tr('طلب جديد', 'New')} (${newOrders.length})',
                        ),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.delivery_dining_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '${s.tr('طلبات حالية', 'Current')} (${currentOrders.length})',
                        ),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '${s.tr('الطلبات السابقة', 'Previous')} (${archivedOrders.length})',
                        ),
                      ],
                    ),
                  ),
                  if (_tableManagementEnabled)
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.table_restaurant_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '${s.tr('طاولات الصالة', 'Dining tables')} (${hallOrders.length})',
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _OrdersList(
                    orders: newOrders,
                    dateFormat: dateFormat,
                    emptyTitle: s.tr('لا توجد طلبات جديدة', 'No new orders'),
                    emptySubtitle: s.tr(
                      'ستظهر الطلبات الواردة هنا فور إرسال العميل عبر المنيو أو الواتساب.',
                      'Incoming menu or WhatsApp orders will appear here.',
                    ),
                    onStatusChanged: _handleStatus,
                  ),
                  _OrdersList(
                    orders: currentOrders,
                    dateFormat: dateFormat,
                    emptyTitle: s.tr(
                      'لا توجد طلبات حالية',
                      'No current orders',
                    ),
                    emptySubtitle: s.tr(
                      'بعد قبول السائق ينتقل الطلب هنا مع اسمه وموقعه.',
                      'Accepted orders appear here with driver details.',
                    ),
                    onStatusChanged: _handleStatus,
                    showDriverTracking: true,
                  ),
                  _OrdersList(
                    orders: archivedOrders,
                    dateFormat: dateFormat,
                    emptyTitle: s.tr(
                      'لا توجد طلبات سابقة',
                      'No previous orders',
                    ),
                    emptySubtitle: s.tr(
                      'عند إتمام التوصيل أو إلغاء الطلب، يُحفظ هنا للمراجعة.',
                      'Delivered or cancelled orders are saved here.',
                    ),
                    onStatusChanged: _handleStatus,
                    readOnly: true,
                  ),
                  if (_tableManagementEnabled)
                    _OrdersList(
                      orders: hallOrders,
                      dateFormat: dateFormat,
                      emptyTitle: s.tr(
                        'لا توجد فواتير طاولات مسكّرة',
                        'No closed table receipts',
                      ),
                      emptySubtitle: s.tr(
                        'عند إغلاق حساب الطاولة تظهر الفاتورة هنا وتُحسب ضمن مبيعات الصالة.',
                        'Closed table receipts appear here and count toward dine-in sales.',
                      ),
                      onStatusChanged: _handleStatus,
                      readOnly: true,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OrdersPageHeader extends StatelessWidget {
  const _OrdersPageHeader({
    required this.newCount,
    required this.currentCount,
    required this.archivedCount,
    required this.pendingCount,
    this.hallCount = 0,
    this.tableManagementEnabled = false,
  });

  final int newCount;
  final int currentCount;
  final int archivedCount;
  final int pendingCount;
  final int hallCount;
  final bool tableManagementEnabled;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      color: const Color(0xFFF4F6F8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.tr('إدارة الطلبات', 'Order Management'),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6B1124),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            s.tr(
              'تابع الطلبات الجديدة حتى يقبلها السائق، ثم راقب الطلبات الحالية والأرشيف.',
              'Track new, current, and archived orders.',
            ),
            style: TextStyle(color: Colors.grey.shade700, height: 1.4),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatChip(
                icon: Icons.notifications_active_outlined,
                label: s.tr('بانتظار القبول', 'Awaiting acceptance'),
                value: '$pendingCount',
                color: Colors.green.shade700,
              ),
              _StatChip(
                icon: Icons.fiber_new_outlined,
                label: s.tr('طلب جديد', 'New'),
                value: '$newCount',
                color: Colors.orange.shade800,
              ),
              _StatChip(
                icon: Icons.delivery_dining_outlined,
                label: s.tr('طلبات حالية', 'Current'),
                value: '$currentCount',
                color: const Color(0xFF6B1124),
              ),
              _StatChip(
                icon: Icons.archive_outlined,
                label: s.tr('محفوظة', 'Archived'),
                value: '$archivedCount',
                color: Colors.brown,
              ),
              if (tableManagementEnabled)
                _StatChip(
                  icon: Icons.table_restaurant_outlined,
                  label: s.tr('طاولات الصالة', 'Dining tables'),
                  value: '$hallCount',
                  color: const Color(0xFF0F766E),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrdersList extends StatelessWidget {
  const _OrdersList({
    required this.orders,
    required this.dateFormat,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.onStatusChanged,
    this.readOnly = false,
    this.showDriverTracking = false,
  });

  final List<Order> orders;
  final DateFormat dateFormat;
  final String emptyTitle;
  final String emptySubtitle;
  final Future<void> Function(Order order, OrderStatus status) onStatusChanged;
  final bool readOnly;
  final bool showDriverTracking;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                readOnly ? Icons.inbox_outlined : Icons.receipt_long_outlined,
                size: 56,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                emptyTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6B1124),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                emptySubtitle,
                style: TextStyle(color: Colors.grey.shade600, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final order = orders[index];
        return _AdminOrderCard(
          order: order,
          dateFormat: dateFormat,
          onStatusChanged: onStatusChanged,
          readOnly: readOnly,
          showDriverTracking: showDriverTracking,
        );
      },
    );
  }
}

class _DemoOrdersBanner extends StatelessWidget {
  const _DemoOrdersBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFD49A00).withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.receipt_long_outlined, color: Color(0xFF6B1124)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'وضع تجريبي — طلبات واردة',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6B1124),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'تُعرض طلبات تجريبية لاختبار لوحة التحكم. الطلبات الحقيقية '
                  'من المنيو تُحفظ تلقائياً على الباك إند. عند إتمام التوصيل '
                  'ينتقل الطلب تلقائياً إلى تبويب الطلبات السابقة.',
                  style: TextStyle(color: Colors.brown.shade700, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminOrderCard extends StatelessWidget {
  const _AdminOrderCard({
    required this.order,
    required this.dateFormat,
    required this.onStatusChanged,
    this.readOnly = false,
    this.showDriverTracking = false,
  });

  final Order order;
  final DateFormat dateFormat;
  final Future<void> Function(Order order, OrderStatus status) onStatusChanged;
  final bool readOnly;
  final bool showDriverTracking;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final itemLines = order.items
        .map(
          (item) =>
              '${item.quantity}x ${item.name} (${item.lineTotal.toStringAsFixed(3)} د.ك)',
        )
        .join('\n');
    final canAdvance =
        !readOnly &&
        (AdminAuthService.instance.isSuperAdmin || !order.isHeldByDriver);
    final nextStatus = canAdvance ? order.status.nextStatus : null;
    final nextLabel = canAdvance ? order.status.nextActionLabel : null;
    final paymentLabel = _formatPaymentMethod(context, order.paymentMethod);

    return Card(
      elevation: order.status == OrderStatus.pending ? 4 : 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: order.status == OrderStatus.pending
            ? BorderSide(color: Colors.green.shade400, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _openInvoice(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                        const SizedBox(height: 4),
                        Text(
                          '${s.tr('فاتورة', 'Invoice')} #${order.invoiceNumber ?? order.id.substring(0, 6)}',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                  OrderStatusChip(
                    status: order.status,
                    label: order.cashierStatusLabel,
                  ),
                  if (order.status == OrderStatus.pending) ...[
                    const SizedBox(width: 8),
                    IncomingOrderCountdownBadge(orderId: order.id),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              if (showDriverTracking && order.orderType == OrderType.delivery)
                OrderDriverTrackingCard(order: order),
              _InfoRow(icon: Icons.phone, text: order.phone),
              _InfoRow(icon: Icons.location_on, text: order.address),
              _InfoRow(icon: Icons.payment, text: paymentLabel),
              if (order.receivedByCashierLabel.isNotEmpty)
                _InfoRow(
                  icon: Icons.badge_outlined,
                  text:
                      '${s.tr('الكاشير المستلم', 'Receiving cashier')}: ${order.receivedByCashierLabel}',
                ),
              if (order.targetKitchenName != null &&
                  order.targetKitchenName!.trim().isNotEmpty)
                _InfoRow(
                  icon: Icons.soup_kitchen_outlined,
                  text:
                      '${s.tr('المطبخ', 'Kitchen')}: ${order.targetKitchenName}',
                ),
              const SizedBox(height: 10),
              Text(
                itemLines,
                style: TextStyle(color: Colors.grey.shade800, height: 1.5),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    '${order.totalPrice.toStringAsFixed(3)} د.ك',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.brown,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    dateFormat.format(order.createdAt.toLocal()),
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
              if (order.isHeldByDriver &&
                  !AdminAuthService.instance.isSuperAdmin) ...[
                const SizedBox(height: 12),
                const DriverCustodyLockBadge(),
              ],
              if (nextStatus != null && nextLabel != null) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _actionColor(order.status),
                    ),
                    onPressed: () => onStatusChanged(order, nextStatus),
                    icon: const Icon(Icons.check_circle, color: Colors.white),
                    label: Text(
                      nextLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
              if (readOnly && order.status == OrderStatus.delivered) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        showSendRatingReminderSheet(context, order: order),
                    icon: Icon(
                      order.isRated ? Icons.star : Icons.star_outline,
                      color: const Color(0xFF6B1124),
                    ),
                    label: Text(
                      order.isRated
                          ? s.tr(
                              'التقييم مُرسل / مُكتمل',
                              'Rating sent / completed',
                            )
                          : s.tr('إرسال طلب تقييم', 'Send rating request'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openInvoice(BuildContext context) async {
    var platforms = SalesPlatformConfig.defaults();
    try {
      final settings = await RestaurantSettingsService.instance.load();
      platforms = settings.resolvedSalesPlatforms;
    } catch (_) {}
    if (!context.mounted) return;
    await showAdminOrderDetailsDialog(
      context,
      order: order,
      platforms: platforms,
      showStatusActions:
          AdminAuthService.instance.isSuperAdmin || !order.isHeldByDriver,
      onStatusChanged: (orderId, status) => onStatusChanged(order, status),
    );
  }

  String _formatPaymentMethod(BuildContext context, String? method) {
    final value = (method ?? '').trim();
    final s = AppStrings.read(context);
    if (value.isEmpty) {
      return '${s.paymentMethod}: ${s.tr('غير محددة', 'Not specified')}';
    }
    if (value.toLowerCase() == 'k-net' || value == 'K-Net') {
      return '${s.paymentMethod}: K-Net';
    }
    if (value == 'كاش') return '${s.paymentMethod}: ${s.cash}';
    return '${s.paymentMethod}: $value';
  }

  Color _actionColor(OrderStatus status) {
    return switch (status) {
      OrderStatus.pending => Colors.green.shade700,
      OrderStatus.confirmed => Colors.orange.shade700,
      OrderStatus.preparing => Colors.blue.shade700,
      _ => Colors.brown,
    };
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.brown),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
