import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../../../models/order.dart';
import '../../../services/orders_demo_service.dart';
import '../../../services/orders_service.dart';
import '../../../utils/order_payment_utils.dart';
import 'pos_theme.dart';

class PosPendingPickupPage extends StatelessWidget {
  const PosPendingPickupPage({
    super.key,
    required this.onResumeForSettlement,
  });

  final ValueChanged<Order> onResumeForSettlement;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return ColoredBox(
      color: const Color(0xFFF4F6F8),
      child: StreamBuilder<List<Order>>(
        stream: OrdersService.instance.watchOrders(),
        initialData: OrdersDemoService.loadedOrders,
        builder: (context, snapshot) {
          final open = unsettledPickupOrders(snapshot.data ?? const []);
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.tr('فواتير استلام معلّقة', 'Held pickup orders'),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: PosTheme.headerMaroon,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.tr(
                          'طلبات استلام لم يُدفع ثمنها بعد. اختر فاتورة لتعديل الأصناف ثم الدفع وطباعة الإيصال.',
                          'Pickup orders not paid yet. Select one to edit, pay, and print the receipt.',
                        ),
                        style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
              if (open.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Text(
                      s.tr(
                        'لا توجد فواتير معلّقة',
                        'No held pickup orders',
                      ),
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: open.length,
                  itemBuilder: (context, index) {
                    final order = open[index];
                    return _HeldOrderTile(
                      order: order,
                      onTap: () => onResumeForSettlement(order),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _HeldOrderTile extends StatelessWidget {
  const _HeldOrderTile({required this.order, required this.onTap});

  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
  final s = AppStrings.of(context);
    final time =
        '${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}';
    final invoice = order.invoiceNumber ?? order.id;
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
            child: Icon(Icons.pause_circle_outline, color: PosTheme.orange),
          ),
          title: Text(
            '${s.tr('فاتورة', 'Invoice')} #$invoice — ${order.customerName}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            '${order.phone} • $time • ${order.items.length} ${s.tr('صنف', 'items')}',
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
                s.tr('دفع لاحقاً', 'Pay later'),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}