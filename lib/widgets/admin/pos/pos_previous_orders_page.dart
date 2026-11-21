import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../../../models/order.dart';
import '../../../services/orders_demo_service.dart';
import '../../../services/orders_service.dart';
import '../../../utils/pos_pending_orders.dart';
import 'pos_theme.dart';

class PosPreviousOrdersPage extends StatefulWidget {
  const PosPreviousOrdersPage({super.key});

  @override
  State<PosPreviousOrdersPage> createState() => _PosPreviousOrdersPageState();
}

class _PosPreviousOrdersPageState extends State<PosPreviousOrdersPage>
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
          final all = previousPosWalkInOrders(snapshot.data ?? const []);
          final pickup =
              all.where((order) => order.orderType == OrderType.pickup).toList();
          final dineIn =
              all.where((order) => order.orderType == OrderType.dineIn).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.posPreviousOrders,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: PosTheme.headerMaroon,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.tr(
                        'طلبات الاستلام والطاولات المدفوعة والمغلقة (${all.length}).',
                        'Paid and closed pickup and table orders (${all.length}).',
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
                    indicatorColor: PosTheme.green,
                    tabs: [
                      Tab(text: '${s.tr('استلام', 'Pickup')} (${pickup.length})'),
                      Tab(text: '${s.tr('طاولات', 'Tables')} (${dineIn.length})'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _ClosedList(orders: pickup),
                    _ClosedList(orders: dineIn),
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

class _ClosedList extends StatelessWidget {
  const _ClosedList({required this.orders});

  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    if (orders.isEmpty) {
      return Center(
        child: Text(
          s.tr('لا توجد طلبات مغلقة بعد', 'No closed orders yet'),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        final paidAt = order.paidAt ?? order.createdAt;
        final time =
            '${paidAt.hour.toString().padLeft(2, '0')}:${paidAt.minute.toString().padLeft(2, '0')}';
        final invoice = order.invoiceNumber ?? order.id;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFE8F8EF),
                child: Icon(
                  order.orderType == OrderType.pickup
                      ? Icons.check_circle_outline
                      : Icons.table_bar,
                  color: PosTheme.green,
                ),
              ),
              title: Text(
                '#$invoice — ${order.customerName}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${order.paymentMethod} • $time • ${order.items.length} ${s.tr('صنف', 'items')}',
              ),
              trailing: Text(
                '${order.totalPrice.toStringAsFixed(3)} ${s.tr('د.ك', 'KWD')}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: PosTheme.green,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}