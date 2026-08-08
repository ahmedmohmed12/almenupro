import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/order.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin/order_status_chip.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _firebaseService = FirebaseService();
  OrderStatus? _filterStatus;

  Future<void> _updateStatus(String orderId, OrderStatus status) async {
    try {
      await _firebaseService.updateOrderStatus(orderId, status);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order updated to ${status.name}.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $error')),
      );
    }
  }

  int _countByStatus(List<Order> orders, OrderStatus status) {
    return orders.where((order) => order.status == status).length;
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d • HH:mm');
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
            },
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Customer menu'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<Order>>(
        stream: _firebaseService.watchOrders(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load orders.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final orders = snapshot.data ?? [];
          final filtered = _filterStatus == null
              ? orders
              : orders.where((order) => order.status == _filterStatus).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live orders',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _StatCard(
                            label: 'Total',
                            value: '${orders.length}',
                            color: Colors.white,
                          ),
                          const SizedBox(width: 10),
                          _StatCard(
                            label: 'Pending',
                            value: '${_countByStatus(orders, OrderStatus.pending)}',
                            color: Colors.amber.shade50,
                          ),
                          const SizedBox(width: 10),
                          _StatCard(
                            label: 'Preparing',
                            value:
                                '${_countByStatus(orders, OrderStatus.preparing)}',
                            color: Colors.orange.shade50,
                          ),
                          const SizedBox(width: 10),
                          _StatCard(
                            label: 'Ready',
                            value: '${_countByStatus(orders, OrderStatus.ready)}',
                            color: Colors.green.shade50,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: const Text('All'),
                        selected: _filterStatus == null,
                        onSelected: (_) => setState(() => _filterStatus = null),
                      ),
                    ),
                    ...OrderStatus.values.map(
                      (status) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(status.name),
                          selected: _filterStatus == status,
                          onSelected: (_) {
                            setState(() => _filterStatus = status);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          _filterStatus == null
                              ? 'No orders yet.'
                              : 'No ${_filterStatus!.name} orders.',
                          style: theme.textTheme.titleMedium,
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final order = filtered[index];
                          return _OrderCard(
                            order: order,
                            dateFormat: dateFormat,
                            onStatusChanged: (status) {
                              _updateStatus(order.id, status);
                            },
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

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          Text(label),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.dateFormat,
    required this.onStatusChanged,
  });

  final Order order;
  final DateFormat dateFormat;
  final ValueChanged<OrderStatus> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemSummary = order.items
        .map((item) {
          final options = item.selectedOptions.map((o) => o.name).join(', ');
          final suffix = options.isEmpty ? '' : ' ($options)';
          return '${item.quantity}x ${item.name}$suffix';
        })
        .join('\n');

    return Card(
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
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('Order #${order.id.substring(0, 6)}'),
                    ],
                  ),
                ),
                OrderTypeBadge(orderType: order.orderType),
                const SizedBox(width: 8),
                OrderStatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(icon: Icons.phone_outlined, text: order.phone),
            _InfoRow(icon: Icons.location_on_outlined, text: order.address),
            const SizedBox(height: 12),
            Text(
              itemSummary,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '\$${order.totalPrice.toStringAsFixed(2)}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: AppTheme.brandPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  dateFormat.format(order.createdAt.toLocal()),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<OrderStatus>(
              value: order.status,
              decoration: const InputDecoration(
                labelText: 'Update status',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: OrderStatus.values
                  .map(
                    (status) => DropdownMenuItem(
                      value: status,
                      child: Text(status.name),
                    ),
                  )
                  .toList(),
              onChanged: (status) {
                if (status != null && status != order.status) {
                  onStatusChanged(status);
                }
              },
            ),
          ],
        ),
      ),
    );
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
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
