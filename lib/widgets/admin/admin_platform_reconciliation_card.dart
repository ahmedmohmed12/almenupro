import 'package:flutter/material.dart';

import '../../services/admin_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/super_admin_scope_service.dart';

class AdminPlatformReconciliationCard extends StatefulWidget {
  const AdminPlatformReconciliationCard({super.key});

  @override
  State<AdminPlatformReconciliationCard> createState() =>
      _AdminPlatformReconciliationCardState();
}

class _AdminPlatformReconciliationCardState
    extends State<AdminPlatformReconciliationCard> {
  static const burgundy = Color(0xFF6B1124);

  var _loading = true;
  var _days = 1;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _restaurantId {
    if (AdminAuthService.instance.isRestaurantAdmin ||
        AdminAuthService.instance.isCashier) {
      return AdminAuthService.instance.restaurantId ??
          ApiService.defaultRestaurantId;
    }
    return SuperAdminScopeService.instance.effectiveRestaurantId;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.instance.fetchPlatformReconciliation(
        restaurantId: _restaurantId,
        days: _days,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  String _money(Object? value) {
    final amount = value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    return amount.toStringAsFixed(3);
  }

  @override
  Widget build(BuildContext context) {
    final channels = (_data?['channels'] as List?) ?? const [];
    final orders = (_data?['orders'] as List?) ?? const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'تسوية المنصات',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: burgundy,
                    ),
                  ),
                ),
                DropdownButton<int>(
                  value: _days,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('اليوم')),
                    DropdownMenuItem(value: 7, child: Text('7 أيام')),
                    DropdownMenuItem(value: 30, child: Text('30 يوم')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _days = value);
                    _load();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'المطلوب من العميل مقابل صافي التاجر. رسوم توصيل المنصة لا تدخل صافي التاجر، ورسوم توصيل المطعم تظهر منفصلة.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const LinearProgressIndicator(color: burgundy)
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red))
            else ...[
              for (final raw in channels)
                if (raw is Map)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${raw['platformLabel'] ?? raw['platform']}: ${raw['orders']} طلب • مطلوب ${_money(raw['customerPayableTotal'])} • صافي ${_money(raw['netMerchantSales'])} • عمولة ${_money(raw['platformCommission'])} • توصيل منصة ${_money(raw['platformDeliveryFee'])} • توصيل مطعم ${_money(raw['merchantDeliveryFee'])}',
                    ),
                  ),
              if (channels.isEmpty)
                const Text('لا توجد فواتير منصات في هذه الفترة.'),
              const SizedBox(height: 8),
              for (final raw in orders.take(30))
                if (raw is Map) _OrderLine(row: Map<String, dynamic>.from(raw), money: _money),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrderLine extends StatelessWidget {
  const _OrderLine({required this.row, required this.money});

  final Map<String, dynamic> row;
  final String Function(Object? value) money;

  @override
  Widget build(BuildContext context) {
    final items = (row['items'] as List?) ?? const [];
    final itemText = items.whereType<Map>().map((item) {
      final name = item['name'] ?? '';
      final qty = item['quantity'] ?? 1;
      final modifiers = item['modifiersTotal'];
      final discount = item['itemDiscount'];
      return '$qty× $name'
          '${(modifiers is num && modifiers > 0) ? ' +إضافات ${money(modifiers)}' : ''}'
          '${(discount is num && discount > 0) ? ' −خصم ${money(discount)}' : ''}';
    }).join('، ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '#${row['invoiceNumber'] ?? row['orderId']} • ${row['platformLabel']} • ${row['paymentStatus'] ?? row['paymentMethod']}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (itemText.isNotEmpty)
            Text(itemText, style: const TextStyle(color: Colors.black87, height: 1.35)),
          Text(
            'أصناف ${money(row['itemSubtotal'])} • مطلوب ${money(row['customerPayableTotal'])} • صافي ${money(row['netMerchantSales'])} • عمولة ${money(row['platformCommission'])}',
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
