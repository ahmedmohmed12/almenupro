import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/order.dart';
import '../../services/orders_service.dart';
import '../../utils/order_sound.dart';
import 'order_status_chip.dart';

class AdminOrdersPanel extends StatefulWidget {
  const AdminOrdersPanel({
    super.key,
    this.onPendingCountChanged,
  });

  final ValueChanged<int>? onPendingCountChanged;

  @override
  State<AdminOrdersPanel> createState() => AdminOrdersPanelState();
}

class AdminOrdersPanelState extends State<AdminOrdersPanel>
    with SingleTickerProviderStateMixin {
  final _ordersService = OrdersService.instance;
  final Set<String> _knownOrderIds = {};
  var _initialized = false;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void selectNewOrdersTab() {
    _tabController.animateTo(0);
  }

  Future<void> _updateStatus(String orderId, OrderStatus status) async {
    try {
      await _ordersService.updateOrderStatus(orderId, status);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تحديث الحالة: ${status.arabicLabel}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحديث الطلب: $error')),
      );
    }
  }

  void _handleOrdersUpdate(List<Order> orders) {
    final pendingCount =
        orders.where((order) => order.status == OrderStatus.pending).length;
    widget.onPendingCountChanged?.call(pendingCount);

    if (!_initialized) {
      _knownOrderIds
        ..clear()
        ..addAll(orders.map((order) => order.id));
      _initialized = true;
      return;
    }

    for (final order in orders) {
      if (order.status != OrderStatus.pending) continue;
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

  List<Order> _activeOrders(List<Order> orders) {
    final active = orders.where((order) => order.status.isActiveForAdmin).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return active;
  }

  List<Order> _archivedOrders(List<Order> orders) {
    final archived =
        orders.where((order) => order.status.isArchivedForAdmin).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return archived;
  }

  @override
  Widget build(BuildContext context) {
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
                'خطأ في تحميل الطلبات: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final orders = snapshot.data ?? [];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleOrdersUpdate(orders);
        });

        final activeOrders = _activeOrders(orders);
        final archivedOrders = _archivedOrders(orders);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OrdersPageHeader(
              activeCount: activeOrders.length,
              archivedCount: archivedOrders.length,
              pendingCount: orders
                  .where((order) => order.status == OrderStatus.pending)
                  .length,
            ),
            if (_ordersService.isDemoMode) const _DemoOrdersBanner(),
            Material(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
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
                        Text('الطلبات الجديدة (${activeOrders.length})'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text('الطلبات السابقة (${archivedOrders.length})'),
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
                    orders: activeOrders,
                    dateFormat: dateFormat,
                    emptyTitle: 'لا توجد طلبات جديدة',
                    emptySubtitle:
                        'ستظهر الطلبات الواردة هنا فور إرسال العميل عبر المنيو أو الواتساب.',
                    onStatusChanged: _updateStatus,
                  ),
                  _OrdersList(
                    orders: archivedOrders,
                    dateFormat: dateFormat,
                    emptyTitle: 'لا توجد طلبات سابقة',
                    emptySubtitle:
                        'عند إتمام التوصيل أو إلغاء الطلب، يُحفظ هنا للمراجعة.',
                    onStatusChanged: _updateStatus,
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
    required this.activeCount,
    required this.archivedCount,
    required this.pendingCount,
  });

  final int activeCount;
  final int archivedCount;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      color: const Color(0xFFF4F6F8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'إدارة الطلبات',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6B1124),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'تابع الطلبات الجديدة واقبلها، ثم راجع الأرشيف المحفوظ.',
            style: TextStyle(color: Colors.grey.shade700, height: 1.4),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatChip(
                icon: Icons.notifications_active_outlined,
                label: 'بانتظار القبول',
                value: '$pendingCount',
                color: Colors.green.shade700,
              ),
              _StatChip(
                icon: Icons.delivery_dining_outlined,
                label: 'طلبات نشطة',
                value: '$activeCount',
                color: const Color(0xFF6B1124),
              ),
              _StatChip(
                icon: Icons.archive_outlined,
                label: 'محفوظة',
                value: '$archivedCount',
                color: Colors.brown,
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
  });

  final List<Order> orders;
  final DateFormat dateFormat;
  final String emptyTitle;
  final String emptySubtitle;
  final Future<void> Function(String orderId, OrderStatus status) onStatusChanged;
  final bool readOnly;

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
        border: Border.all(color: const Color(0xFFD49A00).withValues(alpha: 0.45)),
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
                  style: TextStyle(
                    color: Colors.brown.shade700,
                    height: 1.4,
                  ),
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
  });

  final Order order;
  final DateFormat dateFormat;
  final Future<void> Function(String orderId, OrderStatus status) onStatusChanged;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final itemLines = order.items
        .map(
          (item) =>
              '${item.quantity}x ${item.name} (${item.lineTotal.toStringAsFixed(3)} د.ك)',
        )
        .join('\n');
    final nextStatus = readOnly ? null : order.status.nextStatus;
    final nextLabel = readOnly ? null : order.status.nextActionLabel;
    final paymentLabel = _formatPaymentMethod(order.paymentMethod);

    return Card(
      elevation: order.status == OrderStatus.pending ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: order.status == OrderStatus.pending
            ? BorderSide(color: Colors.green.shade400, width: 2)
            : BorderSide.none,
      ),
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
                        'فاتورة #${order.invoiceNumber ?? order.id.substring(0, 6)}',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                OrderStatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(icon: Icons.phone, text: order.phone),
            _InfoRow(icon: Icons.location_on, text: order.address),
            _InfoRow(icon: Icons.payment, text: paymentLabel),
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
            if (nextStatus != null && nextLabel != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _actionColor(order.status),
                  ),
                  onPressed: () => onStatusChanged(order.id, nextStatus),
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
          ],
        ),
      ),
    );
  }

  String _formatPaymentMethod(String? method) {
    final value = (method ?? '').trim();
    if (value.isEmpty) return 'طريقة الدفع: غير محددة';
    if (value.toLowerCase() == 'k-net' || value == 'K-Net') {
      return 'طريقة الدفع: K-Net';
    }
    if (value == 'كاش') return 'طريقة الدفع: كاش (Cash)';
    return 'طريقة الدفع: $value';
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
