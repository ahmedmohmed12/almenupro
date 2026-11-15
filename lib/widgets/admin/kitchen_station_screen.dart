import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/order.dart';
import '../../models/sales_platform_config.dart';
import '../../services/admin_auth_service.dart';
import '../../services/orders_service.dart';
import 'scheduled_orders_page.dart';
import '../../services/pos_print_helper.dart';
import '../../services/restaurant_settings_service.dart';
import '../../utils/pos_receipt_html.dart';
import 'admin_corner_toast.dart';
import 'admin_order_details_dialog.dart';
import 'order_status_chip.dart';

class KitchenStationScreen extends StatefulWidget {
  const KitchenStationScreen({super.key, this.onLogout});

  final VoidCallback? onLogout;

  @override
  State<KitchenStationScreen> createState() => _KitchenStationScreenState();
}

class _KitchenStationScreenState extends State<KitchenStationScreen>
    with SingleTickerProviderStateMixin {
  static const _burgundy = Color(0xFF6B1124);

  final _ordersService = OrdersService.instance;
  final List<SalesPlatformConfig> _platforms = SalesPlatformConfig.defaults();
  late final TabController _tabController;

  String get _kitchenId =>
      AdminAuthService.instance.kitchenId?.trim() ?? '';

  String get _kitchenName {
    final name = AdminAuthService.instance.kitchenName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return AdminAuthService.instance.session?.staffName ?? 'المطبخ';
  }

  bool _belongsToKitchen(Order order) {
    if (_kitchenId.isEmpty) return false;
    return (order.targetKitchenId ?? '').trim() == _kitchenId;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    unawaited(RestaurantSettingsService.instance.load());
    unawaited(_ordersService.refreshOrders());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _printKitchen(Order order) async {
    try {
      await PosPrintHelper.printOrder(
        order: order,
        kind: PosReceiptKind.kitchen,
        ignorePermission: true,
      );
      if (!mounted) return;
      AdminCornerToast.success(context, 'تمت طباعة تذكرة المطبخ');
    } catch (error) {
      if (!mounted) return;
      AdminCornerToast.error(
        context,
        error.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> _openDetails(Order order) async {
    await showAdminOrderDetailsDialog(
      context,
      order: order,
      platforms: _platforms,
      showStatusActions: false,
      onStatusChanged: (_, _) async {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d/M • HH:mm');
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        backgroundColor: _burgundy,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_kitchenName, style: const TextStyle(fontSize: 18)),
            Text(
              AdminAuthService.instance.restaurantName ?? '',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: () => _ordersService.refreshOrders(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'خروج',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          const ScheduledKitchenBanner(),
          Expanded(
            child: StreamBuilder<List<Order>>(
        stream: _ordersService.watchOrders(),
        initialData: const [],
        builder: (context, snapshot) {
          final orders = (snapshot.data ?? [])
              .where(_belongsToKitchen)
              .where(
                (order) =>
                    order.status != OrderStatus.pending &&
                    order.status != OrderStatus.scheduled,
              )
              .toList();
          final incoming = orders
              .where(
                (order) =>
                    order.status == OrderStatus.confirmed ||
                    order.status == OrderStatus.inKitchen,
              )
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final current = orders
              .where(
                (order) =>
                    order.status == OrderStatus.preparing ||
                    order.status == OrderStatus.ready,
              )
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final previous = orders
              .where((order) => order.status.isArchivedForAdmin)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          return Column(
            children: [
              Container(
                width: double.infinity,
                color: const Color(0xFFFFF8E8),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Text(
                  'الكاشير يقبل طلب العميل أولاً ويُحسب في ورديته، ثم يظهر هنا طلبات $_kitchenName حسب منطقة التوصيل.',
                  style: const TextStyle(height: 1.35, fontSize: 13),
                ),
              ),
              Material(
                color: Colors.white,
                child: TabBar(
                  controller: _tabController,
                  labelColor: _burgundy,
                  unselectedLabelColor: Colors.grey.shade600,
                  indicatorColor: const Color(0xFFD49A00),
                  tabs: [
                    Tab(text: 'واردة (${incoming.length})'),
                    Tab(text: 'حالية (${current.length})'),
                    Tab(text: 'سابقة (${previous.length})'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _KitchenOrdersList(
                      orders: incoming,
                      dateFormat: dateFormat,
                      emptyTitle: 'لا توجد طلبات واردة',
                      emptySubtitle:
                          'بعد قبول الكاشير يظهر هنا طلب هذه المنطقة فقط.',
                      onOpen: _openDetails,
                      onPrint: _printKitchen,
                    ),
                    _KitchenOrdersList(
                      orders: current,
                      dateFormat: dateFormat,
                      emptyTitle: 'لا توجد طلبات قيد التنفيذ',
                      emptySubtitle:
                          'عندما يحوّل الكاشير الطلب إلى «في الطريق» يظهر هنا.',
                      onOpen: _openDetails,
                      onPrint: _printKitchen,
                    ),
                    _KitchenOrdersList(
                      orders: previous,
                      dateFormat: dateFormat,
                      emptyTitle: 'لا توجد طلبات سابقة',
                      emptySubtitle: 'الطلبات المنتهية أو المرفوضة من الكاشير تظهر هنا.',
                      onOpen: _openDetails,
                      onPrint: _printKitchen,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
            ),
          ),
        ],
      ),
    );
  }
}

class _KitchenOrdersList extends StatelessWidget {
  const _KitchenOrdersList({
    required this.orders,
    required this.dateFormat,
    required this.emptyTitle,
    required this.emptySubtitle,
    this.onOpen,
    this.onPrint,
  });

  final List<Order> orders;
  final DateFormat dateFormat;
  final String emptyTitle;
  final String emptySubtitle;
  final Future<void> Function(Order order)? onOpen;
  final Future<void> Function(Order order)? onPrint;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.soup_kitchen_outlined, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                emptyTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                emptySubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
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
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: onOpen == null ? null : () => onOpen!(order),
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
                    ),
                    OrderStatusChip(status: order.status),
                  ],
                ),
                if (order.receivedByCashierLabel.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'استلمه الكاشير: ${order.receivedByCashierLabel}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B1124),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text('📞 ${order.phone}'),
                if (order.address.trim().isNotEmpty) Text('📍 ${order.address}'),
                const SizedBox(height: 8),
                Text(
                  order.items
                      .map((item) => '${item.quantity}x ${item.name}')
                      .join(' • '),
                ),
                const SizedBox(height: 8),
                Text(
                  dateFormat.format(order.createdAt.toLocal()),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    onPressed: onPrint == null ? null : () => onPrint!(order),
                    icon: const Icon(Icons.print, size: 18),
                    label: const Text('طباعة المطبخ'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
