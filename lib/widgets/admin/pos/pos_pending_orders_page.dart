import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../../../models/order.dart';
import '../../../services/orders_demo_service.dart';
import '../../../services/orders_service.dart';
import '../../../utils/pos_pending_orders.dart';
import 'pos_theme.dart';

class PosPendingOrdersPage extends StatefulWidget {
  const PosPendingOrdersPage({
    super.key,
    required this.onResumePickup,
    required this.onResumeDineIn,
    this.tableManagementEnabled = true,
  });

  final ValueChanged<Order> onResumePickup;
  final ValueChanged<Order> onResumeDineIn;
  final bool tableManagementEnabled;

  @override
  State<PosPendingOrdersPage> createState() => _PosPendingOrdersPageState();
}

class _PosPendingOrdersPageState extends State<PosPendingOrdersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return ColoredBox(
      color: const Color(0xFFF4F6F8),
      child: StreamBuilder<List<Order>>(
        stream: OrdersService.instance.watchOrders(),
        initialData: OrdersDemoService.loadedOrders,
        builder: (context, snapshot) {
          final pickup = pendingPosPickupOrders(snapshot.data ?? const []);
          final dineIn = widget.tableManagementEnabled
              ? pendingPosDineInOrders(snapshot.data ?? const [])
              : <Order>[];
          final total = pickup.length + dineIn.length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.tr('الطلبات المعلّقة', 'Pending orders'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: PosTheme.headerMaroon,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.tr(
                        'طلبات أُرسلت للمطبخ ولم تُسدَّد بعد ($total). اختر فاتورة للتعديل والدفع.',
                        'Sent to kitchen, not paid yet ($total). Open an invoice to edit and pay.',
                      ),
                      style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: TabBar(
                    controller: _tabs,
                    labelColor: PosTheme.headerMaroon,
                    unselectedLabelColor: Colors.grey.shade600,
                    indicatorColor: PosTheme.orange,
                    tabs: [
                      Tab(
                        text:
                            '${s.tr('استلام', 'Pickup')} (${pickup.length})',
                      ),
                      Tab(
                        text: '${s.tr('طاولات', 'Tables')} (${dineIn.length})',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _OrderList(
                      emptyMessage: s.tr(
                        'لا توجد طلبات استلام معلّقة',
                        'No pending pickup orders',
                      ),
                      orders: pickup,
                      icon: Icons.shopping_bag_outlined,
                      onTap: widget.onResumePickup,
                    ),
                    _OrderList(
                      emptyMessage: s.tr(
                        'لا توجد طلبات طاولات معلّقة',
                        'No pending table orders',
                      ),
                      orders: dineIn,
                      icon: Icons.table_restaurant,
                      onTap: widget.onResumeDineIn,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  const _OrderList({
    required this.orders,
    required this.emptyMessage,
    required this.onTap,
    required this.icon,
  });

  final List<Order> orders;
  final String emptyMessage;
  final ValueChanged<Order> onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(child: Text(emptyMessage));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return _PendingOrderTile(
          order: order,
          icon: icon,
          onTap: () => onTap(order),
        );
      },
    );
  }
}

class _PendingOrderTile extends StatelessWidget {
  const _PendingOrderTile({
    required this.order,
    required this.onTap,
    required this.icon,
  });

  final Order order;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final time =
        '${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}';
    final invoice = order.invoiceNumber ?? order.id;
    final tableHint = order.tableId != null && order.tableId!.trim().isNotEmpty
        ? ' • ${order.address}'
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: PosTheme.orangeSoft,
            child: Icon(icon, color: PosTheme.orange),
          ),
          title: Text(
            '${s.tr('فاتورة', 'Invoice')} #$invoice — ${order.customerName}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            '${order.phone} • $time • ${order.items.length} ${s.tr('صنف', 'items')}$tableHint',
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${order.totalPrice.toStringAsFixed(3)} ${s.tr('د.ك', 'KWD')}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: PosTheme.headerMaroon,
                ),
              ),
              Text(
                s.tr('بانتظار الدفع', 'Awaiting payment'),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}