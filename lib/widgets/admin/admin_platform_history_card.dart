import 'package:flutter/material.dart';

import '../../services/admin_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/super_admin_scope_service.dart';

class AdminPlatformHistoryCard extends StatefulWidget {
  const AdminPlatformHistoryCard({super.key});

  @override
  State<AdminPlatformHistoryCard> createState() => _AdminPlatformHistoryCardState();
}

class _AdminPlatformHistoryCardState extends State<AdminPlatformHistoryCard> {
  static const burgundy = Color(0xFF6B1124);

  var _loading = true;
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
      final data = await ApiService.instance.fetchPlatformHistory(
        restaurantId: _restaurantId,
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
    final today = _data?['today'] is Map
        ? Map<String, dynamic>.from(_data!['today'] as Map)
        : const <String, dynamic>{};
    final cash = today['cash'] is Map
        ? Map<String, dynamic>.from(today['cash'] as Map)
        : const <String, dynamic>{};
    final prepaid = today['prepaid'] is Map
        ? Map<String, dynamic>.from(today['prepaid'] as Map)
        : const <String, dynamic>{};
    final customers = _data?['customers'] is Map
        ? Map<String, dynamic>.from(_data!['customers'] as Map)
        : const <String, dynamic>{};
    final orders = (_data?['orders'] as List?) ?? const [];
    final todayOrders = (today['orders'] as List?) ?? const [];

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
                    'كل الطلبات المحفوظة',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: burgundy,
                    ),
                  ),
                ),
                IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
              ],
            ),
            if (_loading)
              const LinearProgressIndicator(color: burgundy)
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red))
            else ...[
              Text(
                'تقرير اليوم ${today['date'] ?? ''} • ${today['orderCount'] ?? 0} طلب • الإجمالي ${_money(today['totalSales'])}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'كاش ${cash['count'] ?? 0} / ${_money(cash['total'])} • مدفوع مسبقاً ${prepaid['count'] ?? 0} / ${_money(prepaid['total'])}',
              ),
              if ((today['cancelledCount'] ?? 0) != 0)
                Text('ملغي اليوم: ${today['cancelledCount']}'),
              const SizedBox(height: 4),
              Text(
                'العملاء المحفوظون برقم الهاتف: ${customers['saved'] ?? 0} من ${customers['scanned'] ?? 0} فاتورة. الأرقام المخفية لم تُحفظ.',
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              const Text(
                'فواتير اليوم',
                style: TextStyle(fontWeight: FontWeight.w700, color: burgundy),
              ),
              const SizedBox(height: 8),
              _OrdersTable(rows: todayOrders, money: _money),
              const SizedBox(height: 16),
              Text(
                'كل الفواتير (${orders.length})',
                style: const TextStyle(fontWeight: FontWeight.w700, color: burgundy),
              ),
              const SizedBox(height: 8),
              _OrdersTable(rows: orders, money: _money),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrdersTable extends StatelessWidget {
  const _OrdersTable({required this.rows, required this.money});

  final List<dynamic> rows;
  final String Function(Object? value) money;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Text('لا توجد فواتير.');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: const WidgetStatePropertyAll(Color(0xFFF8EDEE)),
        columns: const [
          DataColumn(label: Text('رقم الطلب')),
          DataColumn(label: Text('المنصة')),
          DataColumn(label: Text('الوقت')),
          DataColumn(label: Text('الأصناف')),
          DataColumn(label: Text('المبلغ')),
          DataColumn(label: Text('الهاتف')),
          DataColumn(label: Text('الدفع')),
        ],
        rows: [
          for (final raw in rows)
            if (raw is Map)
              DataRow(
                cells: [
                  DataCell(Text('${raw['orderNumber'] ?? ''}')),
                  DataCell(Text('${raw['platformLabel'] ?? raw['platform'] ?? ''}')),
                  DataCell(Text('${raw['createdAtLabel'] ?? ''}')),
                  DataCell(SizedBox(width: 280, child: Text('${raw['items'] ?? ''}'))),
                  DataCell(Text(money(raw['total']))),
                  DataCell(Text('${raw['phone'] ?? ''}')),
                  DataCell(Text('${raw['paymentStatus'] ?? ''}')),
                ],
              ),
        ],
      ),
    );
  }
}
