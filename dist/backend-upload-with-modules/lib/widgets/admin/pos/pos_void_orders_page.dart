import 'package:flutter/material.dart';

import '../../../models/order.dart';
import '../../../services/orders_service.dart';
import '../../../services/pos_operations_service.dart';

class PosVoidOrdersPage extends StatefulWidget {
  const PosVoidOrdersPage({super.key});

  @override
  State<PosVoidOrdersPage> createState() => _PosVoidOrdersPageState();
}

class _PosVoidOrdersPageState extends State<PosVoidOrdersPage> {
  final _ordersService = OrdersService.instance;

  Future<void> _voidOrder(Order order) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إلغاء الطلب (Void)'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: 'سبب الإلغاء',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('تراجع')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأكيد الإلغاء')),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      reasonController.dispose();
      return;
    }

    final reason = reasonController.text.trim();
    reasonController.dispose();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال سبب الإلغاء')),
      );
      return;
    }

    try {
      final cashier = PosOperationsService.instance.cashierSession;
      await PosOperationsService.instance.voidOrder(
        orderId: order.id,
        reason: reason,
        performedById: cashier?.staff.id,
        performedByName: cashier?.staff.name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إلغاء الطلب')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'إلغاء الطلبات (Void)',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<List<Order>>(
              stream: _ordersService.watchOrders(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF6B1124)),
                  );
                }

                final orders = (snapshot.data ?? const [])
                    .where((order) => order.status != OrderStatus.cancelled)
                    .toList()
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

                if (orders.isEmpty) {
                  return const Center(child: Text('لا توجد طلبات قابلة للإلغاء'));
                }

                return ListView.separated(
                  itemCount: orders.length.clamp(0, 50),
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    return ListTile(
                      title: Text(
                        '${order.customerName.isNotEmpty ? order.customerName : 'عميل'} — ${order.totalPrice.toStringAsFixed(3)} د.ك',
                      ),
                      subtitle: Text(
                        '${order.status.arabicLabel} • ${order.createdAt.toLocal()}',
                      ),
                      trailing: OutlinedButton(
                        onPressed: () => _voidOrder(order),
                        child: const Text('Void'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
