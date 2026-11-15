import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/dining_table.dart';
import '../models/order.dart';
import '../providers/customer_session_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/order_type_provider.dart';
import '../services/dining_tables_service.dart';
import '../services/table_floor_live_service.dart';
import '../theme/app_theme.dart';
import '../widgets/language_toggle_button.dart';
import 'table_qr_ordering_screen.dart';

class TableQrPortalScreen extends StatefulWidget {
  const TableQrPortalScreen({
    super.key,
    required this.branchId,
    required this.tableId,
  });

  final String branchId;
  final String tableId;

  @override
  State<TableQrPortalScreen> createState() => _TableQrPortalScreenState();
}

class _TableQrPortalScreenState extends State<TableQrPortalScreen> {
  var _loading = true;
  String? _error;
  String _restaurantName = '';
  String _restaurantSlug = '';
  String _tableName = '';
  String _zone = '';
  DiningTable? _table;
  var _busy = false;
  StreamSubscription<List<Map<String, dynamic>>>? _liveSub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await DiningTablesService.instance.fetchPublicTable(
        branchId: widget.branchId,
        tableId: widget.tableId,
      );
      if (!mounted) return;
      setState(() {
        _table = result.table;
        _tableName = result.table.displayName;
        _zone = result.table.zone;
        _restaurantName = result.restaurant['name']?.toString() ?? '';
        _restaurantSlug =
            result.restaurant['slug']?.toString() ??
            result.restaurant['id']?.toString() ??
            widget.branchId;
        _loading = false;
      });
      context.read<CustomerSessionProvider>().bindDineInTable(
        tableId: result.table.id,
        tableName: result.table.displayName,
        restaurantId: result.restaurant['id']?.toString(),
        tableZone: result.table.zone,
      );
      context.read<OrderTypeProvider>().setOrderType(OrderType.dineIn);
      _watchLive(result.restaurant['id']?.toString() ?? widget.branchId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _watchLive(String restaurantId) {
    _liveSub?.cancel();
    _liveSub = TableFloorLiveService.instance.watch(restaurantId).listen((
      overlays,
    ) {
      if (!mounted || _table == null) return;
      Map<String, dynamic>? overlay;
      for (final entry in overlays) {
        if (entry['tableId']?.toString() == _table!.id) {
          overlay = entry;
          break;
        }
      }
      if (overlay == null) return;
      setState(() {
        _table = TableFloorLiveService.instance.mergeOverlay(_table!, overlay);
      });
    });
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    super.dispose();
  }

  Future<void> _openMenu() async {
    if (_table?.isAwaitingCheck ?? false) {
      final strings = AppStrings.read(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.tr(
              'تم طلب الحساب ولا يمكن إضافة أصناف جديدة',
              'The bill was requested; new items cannot be added',
            ),
          ),
        ),
      );
      return;
    }
    final tableId = widget.tableId;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TableQrOrderingScreen(
          branchId: widget.branchId,
          tableId: tableId,
          restaurantId:
              context.read<CustomerSessionProvider>().dineInRestaurantId,
          tableName: _tableName,
          zone: _zone,
          restaurantName: _restaurantName,
          restaurantSlug: _restaurantSlug,
        ),
      ),
    );
  }

  Future<void> _callWaiter() async {
    final strings = AppStrings.read(context);
    final noteController = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.tr('طلب الويتر', 'Call waiter'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                strings.tr(
                  'أضف ملاحظة سريعة للويتر (اختياري)',
                  'Add a quick note for the waiter (optional)',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: strings.tr(
                    'مثال: مناديل إضافية / كرسي أطفال',
                    'e.g. extra napkins / child seat',
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(strings.tr('إرسال الطلب', 'Send request')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(strings.cancel),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;
    final restaurantId =
        context.read<CustomerSessionProvider>().dineInRestaurantId ??
        widget.branchId;
    setState(() => _busy = true);
    try {
      final table = await DiningTablesService.instance.callWaiterPublic(
        branchId: widget.branchId,
        tableId: widget.tableId,
        note: noteController.text.trim(),
      );
      unawaited(TableFloorLiveService.instance.publish(table, restaurantId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Color(0xFF3B82F6),
          content: Text(
            strings.tr(
              'تم إرسال طلب الويتر إلى الصالة',
              'The waiter request was sent',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      noteController.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestCheck() async {
    final strings = AppStrings.read(context);
    final currentTable = _table;
    if (currentTable == null || currentTable.activeSession?.hasItems != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.tr(
              'لا توجد أصناف في حساب الطاولة حالياً',
              'There are no items on this table bill',
            ),
          ),
        ),
      );
      return;
    }
    if (currentTable.isAwaitingCheck) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.tr(
              'تم إرسال طلب الحساب بالفعل',
              'The bill request has already been sent',
            ),
          ),
        ),
      );
      return;
    }
    final request = await Navigator.of(context).push<_BillRequest>(
      MaterialPageRoute(
        builder: (_) => _TableBillScreen(
          table: currentTable,
          restaurantName: _restaurantName,
        ),
      ),
    );
    if (request == null || !mounted) return;
    final restaurantId =
        context.read<CustomerSessionProvider>().dineInRestaurantId ??
        widget.branchId;
    final session = currentTable.activeSession!;
    final optimisticTable = currentTable.copyWith(
      status: DiningTableStatus.awaitingCheck,
      activeSession: session.copyWith(
        checkRequested: true,
        checkRequestedAt: DateTime.now().toUtc(),
        tipAmount: request.tipAmount,
        paymentMethod: request.paymentMethod,
        billTotal: currentTable.sessionAmount + request.tipAmount,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    setState(() {
      _table = optimisticTable;
      _busy = true;
    });
    unawaited(
      TableFloorLiveService.instance.publish(optimisticTable, restaurantId),
    );
    try {
      final table = await DiningTablesService.instance.requestCheckPublic(
        branchId: widget.branchId,
        tableId: widget.tableId,
        tipAmount: request.tipAmount,
        paymentMethod: request.paymentMethod,
      );
      if (mounted) setState(() => _table = table);
      unawaited(TableFloorLiveService.instance.publish(table, restaurantId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text(
            strings.tr('تم إرسال طلب الحساب', 'Check request sent'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _table = currentTable);
      unawaited(
        TableFloorLiveService.instance.publish(currentTable, restaurantId),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Directionality(
      textDirection: context.watch<LocaleProvider>().textDirection,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
        floatingActionButton: const Material(
          color: Colors.white,
          elevation: 3,
          shape: CircleBorder(),
          child: LanguageToggleButton(compact: true),
        ),
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.brandMaroon),
                )
              : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: Text(
                            strings.tr('إعادة المحاولة', 'Try again'),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(20, 20, 20, 24),
                        children: [
                          Text(
                            _restaurantName.isEmpty
                                ? 'AlMenuPro'
                                : _restaurantName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.brandMaroon,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$_tableName${_zone.isEmpty ? '' : ' • $_zone'}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 22),
                          _ActionCard(
                            emoji: '🍽️',
                            title: strings.tr('قائمة الطعام', 'Menu'),
                            subtitle: strings.tr(
                              'تصفح أصنافنا',
                              'Browse our catalog',
                            ),
                            color: AppTheme.brandMaroon,
                            onTap: _busy || (_table?.isAwaitingCheck ?? false)
                                ? null
                                : _openMenu,
                          ),
                          const SizedBox(height: 12),
                          _ActionCard(
                            emoji: '🔔',
                            title: strings.tr('طلب الويتر', 'Call waiter'),
                            subtitle: strings.tr(
                              'اطلب مساعدة من الصالة',
                              'Ask the floor team for help',
                            ),
                            color: const Color(0xFF3B82F6),
                            onTap: _busy ? null : _callWaiter,
                          ),
                          const SizedBox(height: 12),
                          _ActionCard(
                            emoji: '🧾',
                            title: strings.tr('طلب الحساب', 'Request check'),
                            subtitle: strings.tr(
                              _table?.isAwaitingCheck == true
                                  ? 'تم إبلاغ الكاشير'
                                  : 'اعرض الفاتورة واختر طريقة الدفع',
                              _table?.isAwaitingCheck == true
                                  ? 'Cashier notified'
                                  : 'View the bill and choose payment',
                            ),
                            color: const Color(0xFFEF4444),
                            onTap: _busy ? null : _requestCheck,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _BillRequest {
  const _BillRequest({required this.tipAmount, required this.paymentMethod});

  final double tipAmount;
  final String paymentMethod;
}

class _TableBillScreen extends StatefulWidget {
  const _TableBillScreen({required this.table, required this.restaurantName});

  final DiningTable table;
  final String restaurantName;

  @override
  State<_TableBillScreen> createState() => _TableBillScreenState();
}

class _TableBillScreenState extends State<_TableBillScreen> {
  static const _tipOptions = <double>[0, 0.5, 1, 2, 5];
  double _tip = 0;

  List<Map<String, dynamic>> get _items =>
      widget.table.activeSession?.cartItems ?? const [];

  double _number(dynamic value) =>
      (value as num?)?.toDouble() ??
      double.tryParse(value?.toString() ?? '') ??
      0;

  double _quantity(Map<String, dynamic> item) {
    final value = _number(item['quantity']);
    return value > 0 ? value : 1;
  }

  double _unitPrice(Map<String, dynamic> item) =>
      _number(item['unitPrice'] ?? item['unit_price'] ?? item['price']);

  double _lineTotal(Map<String, dynamic> item) {
    final explicit = _number(item['lineTotal'] ?? item['line_total']);
    return explicit > 0 ? explicit : _unitPrice(item) * _quantity(item);
  }

  String _itemName(Map<String, dynamic> item, bool isArabic) {
    final localized = isArabic
        ? item['nameAr'] ?? item['name_ar']
        : item['nameEn'] ?? item['name_en'];
    return (localized ?? item['name'] ?? item['menuItem']?['name'] ?? '')
        .toString();
  }

  void _choosePayment(String method) {
    Navigator.of(
      context,
    ).pop(_BillRequest(tipAmount: _tip, paymentMethod: method));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final subtotal = widget.table.sessionAmount;
    final total = subtotal + _tip;

    return Directionality(
      textDirection: context.watch<LocaleProvider>().textDirection,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(strings.tr('فاتورة مصغرة', 'Mini invoice')),
          backgroundColor: Colors.white,
          foregroundColor: AppTheme.brandMaroon,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Text(
                widget.restaurantName.isEmpty
                    ? 'AlMenuPro'
                    : widget.restaurantName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.brandMaroon,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.table.displayName,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      for (final item in _items) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                '${_quantity(item).toStringAsFixed(0)} × '
                                '${_itemName(item, strings.isArabic)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              '${_lineTotal(item).toStringAsFixed(3)} ${strings.currency}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 22),
                      ],
                      _BillTotalRow(
                        label: strings.subtotal,
                        amount: subtotal,
                        currency: strings.currency,
                      ),
                      if (_tip > 0)
                        _BillTotalRow(
                          label: strings.tr('الإكرامية', 'Tip'),
                          amount: _tip,
                          currency: strings.currency,
                        ),
                      const Divider(height: 24),
                      _BillTotalRow(
                        label: strings.tr('الإجمالي', 'Total'),
                        amount: total,
                        currency: strings.currency,
                        emphasized: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                strings.tr('اختر الإكرامية', 'Select a tip'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tip in _tipOptions)
                    ChoiceChip(
                      selected: _tip == tip,
                      onSelected: (_) => setState(() => _tip = tip),
                      label: Text(
                        tip == 0
                            ? strings.tr('بدون', 'No tip')
                            : '${tip.toStringAsFixed(tip % 1 == 0 ? 0 : 1)} ${strings.currency}',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                strings.tr('طريقة الدفع', 'Payment method'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _choosePayment('cash'),
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(strings.tr('كاش', 'Cash')),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        minimumSize: const Size.fromHeight(54),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _choosePayment('knet'),
                      icon: const Icon(Icons.credit_card),
                      label: const Text('Knet'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        minimumSize: const Size.fromHeight(54),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                strings.tr(
                  'باختيار طريقة الدفع سيتم إبلاغ الكاشير وإيقاف إضافة أصناف جديدة.',
                  'Choosing payment notifies the cashier and locks new item additions.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BillTotalRow extends StatelessWidget {
  const _BillTotalRow({
    required this.label,
    required this.amount,
    required this.currency,
    this.emphasized = false,
  });

  final String label;
  final double amount;
  final String currency;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: emphasized ? AppTheme.brandMaroon : null,
      fontSize: emphasized ? 18 : 14,
      fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text('${amount.toStringAsFixed(3)} $currency', style: style),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 36)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
