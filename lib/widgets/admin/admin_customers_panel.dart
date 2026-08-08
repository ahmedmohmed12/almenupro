import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/customer.dart';
import '../../models/order.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import 'admin_breakpoints.dart';
import 'order_status_chip.dart';

class AdminCustomersPanel extends StatefulWidget {
  const AdminCustomersPanel({super.key});

  @override
  State<AdminCustomersPanel> createState() => _AdminCustomersPanelState();
}

class _AdminCustomersPanelState extends State<AdminCustomersPanel> {
  late Future<List<Customer>> _customersFuture;
  String? _selectedCustomerId;

  @override
  void initState() {
    super.initState();
    _customersFuture = ApiService.instance.fetchCustomers();
  }

  Future<void> _reloadCustomers() async {
    setState(() {
      _customersFuture = ApiService.instance.fetchCustomers();
      _selectedCustomerId = null;
    });
    await _customersFuture;
  }

  void _openCustomer(String customerId) {
    setState(() => _selectedCustomerId = customerId);
  }

  void _backToList() {
    setState(() => _selectedCustomerId = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedCustomerId != null) {
      return AdminCustomerDetailView(
        customerId: _selectedCustomerId!,
        onBack: _backToList,
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CustomersHeader(onRefresh: _reloadCustomers),
          Expanded(
            child: FutureBuilder<List<Customer>>(
              future: _customersFuture,
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
                        'خطأ في تحميل العملاء: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final customers = snapshot.data ?? [];
                if (customers.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people_outline,
                              size: 56, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text(
                            'لا يوجد عملاء مسجلون بعد',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF6B1124),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'سيُسجَّل العملاء تلقائياً عند إتمام أول طلب.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: customers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final customer = customers[index];
                    return _CustomerListCard(
                      customer: customer,
                      onTap: () => _openCustomer(customer.id),
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

class AdminCustomerDetailView extends StatefulWidget {
  const AdminCustomerDetailView({
    super.key,
    required this.customerId,
    required this.onBack,
  });

  final String customerId;
  final VoidCallback onBack;

  @override
  State<AdminCustomerDetailView> createState() => _AdminCustomerDetailViewState();
}

class _AdminCustomerDetailViewState extends State<AdminCustomerDetailView> {
  late Future<CustomerDetailData> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = ApiService.instance.fetchCustomerDetail(widget.customerId);
  }

  Future<void> _reload() async {
    setState(() {
      _detailFuture = ApiService.instance.fetchCustomerDetail(widget.customerId);
    });
    await _detailFuture;
  }

  List<Order> _parseOrders(CustomerDetailData detail) {
    return detail.rawOrders
        .map(
          (raw) => Order.fromMap(
            raw['id']?.toString() ?? '',
            raw,
          ),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d/M/yyyy • HH:mm');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_forward),
                  tooltip: 'رجوع',
                ),
                const Expanded(
                  child: Text(
                    'ملف العميل',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6B1124),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh, color: AppTheme.brandOrange),
                  tooltip: 'تحديث',
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<CustomerDetailData>(
              future: _detailFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF6B1124)),
                  );
                }

                if (snapshot.hasError || !snapshot.hasData) {
                  return Center(
                    child: Text('تعذر تحميل بيانات العميل: ${snapshot.error}'),
                  );
                }

                final detail = snapshot.data!;
                final customer = detail.customer;
                final orders = _parseOrders(detail);

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    _CustomerProfileCard(customer: customer),
                    const SizedBox(height: 20),
                    Text(
                      'سجل الطلبات (${orders.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6B1124),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (orders.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('لا توجد طلبات سابقة لهذا العميل.'),
                      )
                    else
                      ...orders.map(
                        (order) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _CustomerOrderCard(
                            order: order,
                            dateFormat: dateFormat,
                          ),
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

class _CustomersHeader extends StatelessWidget {
  const _CustomersHeader({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.brandOrange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.people, color: AppTheme.brandOrange),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'العملاء',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6B1124),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'قائمة العملاء المسجلين وعناوينهم',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, color: AppTheme.brandOrange),
            tooltip: 'تحديث',
          ),
        ],
      ),
    );
  }
}

class _CustomerListCard extends StatelessWidget {
  const _CustomerListCard({
    required this.customer,
    required this.onTap,
  });

  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.brandMaroon.withValues(alpha: 0.12),
                child: Text(
                  customer.customerName.trim().isNotEmpty
                      ? customer.customerName.trim()[0]
                      : '?',
                  style: const TextStyle(
                    color: AppTheme.brandMaroon,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.customerName.trim().isNotEmpty
                          ? customer.customerName
                          : 'عميل بدون اسم',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      customer.phone,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    if (customer.formattedAddress.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        customer.formattedAddress,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.brandOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${customer.totalOrders} طلب',
                      style: const TextStyle(
                        color: AppTheme.brandMaroon,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Icon(Icons.chevron_left, color: Colors.grey.shade500),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerProfileCard extends StatelessWidget {
  const _CustomerProfileCard({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              customer.customerName.trim().isNotEmpty
                  ? customer.customerName
                  : 'عميل بدون اسم',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6B1124),
              ),
            ),
            const SizedBox(height: 12),
            _ProfileRow(icon: Icons.phone, label: 'الهاتف', value: customer.phone),
            if (customer.formattedAddress.trim().isNotEmpty)
              _ProfileRow(
                icon: Icons.location_on_outlined,
                label: 'العنوان',
                value: customer.formattedAddress,
              ),
            if (customer.governorate.trim().isNotEmpty)
              _ProfileRow(
                icon: Icons.map_outlined,
                label: 'المحافظة',
                value: customer.governorate,
              ),
            if (customer.areaName.trim().isNotEmpty)
              _ProfileRow(
                icon: Icons.place_outlined,
                label: 'المنطقة',
                value: customer.areaName,
              ),
            _ProfileRow(
              icon: Icons.receipt_long_outlined,
              label: 'إجمالي الطلبات',
              value: '${customer.totalOrders}',
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.brandOrange),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerOrderCard extends StatelessWidget {
  const _CustomerOrderCard({
    required this.order,
    required this.dateFormat,
  });

  final Order order;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final itemLines = order.items
        .map(
          (item) =>
              '${item.quantity}x ${item.name} (${item.lineTotal.toStringAsFixed(3)} د.ك)',
        )
        .join('\n');

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'فاتورة #${order.invoiceNumber ?? order.id.substring(0, 8)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                OrderStatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              dateFormat.format(order.createdAt.toLocal()),
              style: TextStyle(color: Colors.grey.shade600),
            ),
            if (order.address.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                order.address,
                style: TextStyle(color: Colors.grey.shade700, height: 1.35),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              itemLines,
              style: TextStyle(color: Colors.grey.shade800, height: 1.45),
            ),
            const SizedBox(height: 10),
            Text(
              '${order.totalPrice.toStringAsFixed(3)} د.ك',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.brandMaroon,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
