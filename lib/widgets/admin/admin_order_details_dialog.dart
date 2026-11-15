import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/delivery_zone.dart';
import '../../models/order.dart';
import '../../models/sales_platform_config.dart';
import '../../services/admin_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/orders_demo_service.dart';
import '../../services/pos_print_helper.dart';
import '../../utils/pos_receipt_html.dart';
import 'incoming_order_countdown_badge.dart';
import 'order_driver_tracking_card.dart';
import 'driver_handshake_banners.dart';

Future<void> showAdminOrderDetailsDialog(
  BuildContext context, {
  required Order order,
  required List<SalesPlatformConfig> platforms,
  required Future<void> Function(String orderId, OrderStatus status) onStatusChanged,
  bool showStatusActions = true,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AdminOrderDetailsDialog(
      order: order,
      platforms: platforms,
      onStatusChanged: onStatusChanged,
      showStatusActions: showStatusActions,
    ),
  );
}

class AdminOrderDetailsDialog extends StatefulWidget {
  const AdminOrderDetailsDialog({
    super.key,
    required this.order,
    required this.platforms,
    required this.onStatusChanged,
    this.showStatusActions = true,
  });

  final Order order;
  final List<SalesPlatformConfig> platforms;
  final Future<void> Function(String orderId, OrderStatus status) onStatusChanged;
  final bool showStatusActions;

  @override
  State<AdminOrderDetailsDialog> createState() => _AdminOrderDetailsDialogState();
}

class _AdminOrderDetailsDialogState extends State<AdminOrderDetailsDialog> {
  late Order _order;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  Order get order => _order;
  List<SalesPlatformConfig> get platforms => widget.platforms;
  Future<void> Function(String orderId, OrderStatus status) get onStatusChanged =>
      widget.onStatusChanged;
  bool get showStatusActions => widget.showStatusActions;

  SalesPlatformConfig get _platform =>
      PlatformCatalog.resolve(order.orderSource, platforms);

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d/M/yyyy • HH:mm');
    final orderId = order.invoiceNumber ?? order.id;
    final nextStatus = order.status.nextStatus;
    final nextLabel = order.status.nextActionLabel;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              decoration: BoxDecoration(
                color: _platform.color.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(
                  bottom: BorderSide(color: _platform.color.withValues(alpha: 0.2)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'طلب #$orderId',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF6B1124),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateFormat.format(order.createdAt.toLocal()),
                          style: const TextStyle(color: Color(0xFF666666)),
                        ),
                      ],
                    ),
                  ),
                  if (order.status == OrderStatus.pending) ...[
                    IncomingOrderCountdownBadge(orderId: order.id),
                    const SizedBox(width: 8),
                  ],
                  SalesPlatformBadge(platform: _platform),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MetaTile(
                      icon: Icons.person_outline,
                      label: 'العميل',
                      value: order.customerName,
                    ),
                    _MetaTile(
                      icon: Icons.phone_outlined,
                      label: 'الهاتف',
                      value: order.phone,
                    ),
                    if (_platform.isExternal &&
                        (order.externalOrderId?.isNotEmpty ?? false))
                      _MetaTile(
                        icon: Icons.tag,
                        label: 'رقم الطلب على المنصة',
                        value: '#${order.externalOrderId}',
                        highlight: true,
                      ),
                    _DeliveryContactEditor(
                      order: order,
                      onUpdated: (updated) => setState(() => _order = updated),
                    ),
                    if (order.orderType == OrderType.delivery ||
                        _platform.isLocal) ...[
                      if ((order.governorate?.isNotEmpty ?? false) ||
                          (order.areaName?.isNotEmpty ?? false))
                        _MetaTile(
                          icon: Icons.map_outlined,
                          label: 'المنطقة',
                          value: [
                            order.governorate,
                            order.areaName,
                          ].whereType<String>().where((v) => v.isNotEmpty).join(' — '),
                        ),
                    ],
                    if (order.settlementLabel.isNotEmpty)
                      _MetaTile(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'تحصيل السائق',
                        value: order.isCashOnDelivery
                            ? 'CASH ON DELIVERY'
                            : 'PREPAID / ONLINE',
                        highlight: true,
                      ),
                    _MetaTile(
                      icon: Icons.payment_outlined,
                      label: 'الدفع',
                      value: order.paymentMethod ?? 'غير محدد',
                    ),
                    if (order.isPlatformPriceLocked)
                      _PlatformSettlementEditor(
                        order: order,
                        onUpdated: (updated) => setState(() => _order = updated),
                      ),
                    _MetaTile(
                      icon: Icons.badge_outlined,
                      label: 'الكاشير المستلم',
                      value: order.receivedByCashierLabel.isNotEmpty
                          ? order.receivedByCashierLabel
                          : 'لم يُستلم بعد من كاشير',
                      highlight: order.receivedByCashierLabel.isNotEmpty,
                    ),
                    if (order.acceptedByLabel.isNotEmpty)
                      _MetaTile(
                        icon: Icons.verified_user_outlined,
                        label: 'قَبِل الطلب',
                        value: order.acceptedByLabel,
                        highlight: true,
                      ),
                    _MetaTile(
                      icon: Icons.local_shipping_outlined,
                      label: 'النوع',
                      value: switch (order.orderType) {
                        OrderType.pickup => 'استلام',
                        OrderType.dineIn => 'صالة',
                        OrderType.delivery => 'توصيل',
                        OrderType.scheduledDelivery => 'توصيل مجدول',
                      },
                    ),
                    const SizedBox(height: 16),
                    if (order.orderType == OrderType.delivery) ...[
                      if (AdminAuthService.instance.isSuperAdmin)
                        OrderDriverTrackingCard(order: order),
                      CashierHandshakePanel(order: order),
                      const SizedBox(height: 8),
                    ],
                    _OrderStatusTimelineCard(order: order),
                    const SizedBox(height: 12),
                    const Text(
                      'الأصناف',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    ...order.items.map(_OrderItemTile.new),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          if ((order.subtotal ?? 0) > 0)
                            _TotalRow(
                              label: 'المجموع الفرعي',
                              value: order.subtotal!.toStringAsFixed(3),
                            ),
                          if ((order.deliveryFee ?? 0) > 0)
                            _TotalRow(
                              label: 'التوصيل',
                              value: order.deliveryFee!.toStringAsFixed(3),
                            ),
                          _TotalRow(
                            label: 'المطلوب من العميل',
                            value: order.customerPayable.toStringAsFixed(3),
                            bold: true,
                          ),
                          if (order.isPlatformPriceLocked)
                            _TotalRow(
                              label: 'صافي مبيعات المطعم',
                              value: order.merchantSales.toStringAsFixed(3),
                              muted: true,
                            ),
                          if ((order.platformCommission ?? 0) > 0) ...[
                            const Divider(height: 16),
                            _TotalRow(
                              label: 'عمولة المنصة',
                              value: '- ${order.platformCommission!.toStringAsFixed(3)}',
                              muted: true,
                            ),
                            _TotalRow(
                              label: 'صافي المطعم',
                              value: order.netRevenue.toStringAsFixed(3),
                              bold: true,
                              color: _platform.color,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await PosPrintHelper.printOrder(
                              order: order,
                              kind: PosReceiptKind.kitchen,
                            );
                          },
                          icon: const Icon(Icons.print, size: 18),
                          label: const Text('طباعة مطبخ'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await PosPrintHelper.printOrder(
                              order: order,
                              kind: PosReceiptKind.customer,
                            );
                          },
                          icon: const Icon(Icons.receipt_long, size: 18),
                          label: const Text('طباعة فاتورة'),
                        ),
                      ),
                    ],
                  ),
                  if (order.isHeldByDriver && !showStatusActions) ...[
                    const SizedBox(height: 8),
                    const DriverCustodyLockBadge(),
                  ],
                  if (showStatusActions && nextStatus != null && nextLabel != null) ...[
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6B1124),
                        minimumSize: const Size.fromHeight(46),
                      ),
                      onPressed: () async {
                        await onStatusChanged(order.id, nextStatus);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(nextLabel),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryContactEditor extends StatefulWidget {
  const _DeliveryContactEditor({
    required this.order,
    required this.onUpdated,
  });

  final Order order;
  final ValueChanged<Order> onUpdated;

  @override
  State<_DeliveryContactEditor> createState() => _DeliveryContactEditorState();
}

class _DeliveryContactEditorState extends State<_DeliveryContactEditor> {
  late Order _order;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  Future<void> _edit() async {
    final updated = await showDialog<Order>(
      context: context,
      builder: (context) => _ZoneAddressDialog(order: _order),
    );
    if (!mounted || updated == null) return;
    setState(() => _order = updated);
    widget.onUpdated(updated);
    final kitchen = (updated.targetKitchenName ?? '').trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          kitchen.isEmpty
              ? 'تم حفظ العنوان وطباعة التذكرة بدون تغيير المبلغ'
              : 'تم توجيه التذكرة إلى $kitchen وطباعتها بدون تغيير المبلغ',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zone = [
      _order.governorate,
      _order.areaName,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' — ');
    final kitchen = (_order.targetKitchenName ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetaTile(
          icon: Icons.location_on_outlined,
          label: 'العنوان',
          value: _order.address.isEmpty ? '—' : _order.address,
        ),
        if (zone.isNotEmpty)
          _MetaTile(
            icon: Icons.map_outlined,
            label: 'منطقة ألمينو',
            value: zone,
          ),
        if (kitchen.isNotEmpty)
          _MetaTile(
            icon: Icons.soup_kitchen_outlined,
            label: 'مطبخ التذكرة',
            value: kitchen,
          ),
        if (_order.deliveryInstructions.trim().isNotEmpty)
          _MetaTile(
            icon: Icons.notes_outlined,
            label: 'تعليمات التوصيل',
            value: _order.deliveryInstructions,
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _edit,
            icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
            label: const Text('اختيار المنطقة والعنوان'),
          ),
        ),
      ],
    );
  }
}

class _ZoneAddressDialog extends StatefulWidget {
  const _ZoneAddressDialog({required this.order});

  final Order order;

  @override
  State<_ZoneAddressDialog> createState() => _ZoneAddressDialogState();
}

class _ZoneAddressDialogState extends State<_ZoneAddressDialog> {
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _notes;
  List<DeliveryZone> _zones = const [];
  String _zoneId = '';
  var _loadingZones = true;
  var _saving = false;
  var _disposed = false;

  void _onFieldChanged() {
    if (!_disposed && mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _address = TextEditingController(text: widget.order.address);
    _phone = TextEditingController(text: widget.order.phone);
    _notes = TextEditingController(text: widget.order.deliveryInstructions);
    _zoneId = widget.order.deliveryZoneId ?? '';
    for (final controller in [_address, _phone, _notes]) {
      controller.addListener(_onFieldChanged);
    }
    _loadZones();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final controller in [_address, _phone, _notes]) {
      controller.removeListener(_onFieldChanged);
    }
    _address.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadZones() async {
    try {
      final zones = await ApiService.instance.fetchDeliveryZones(activeOnly: true);
      if (!mounted) return;
      setState(() {
        _zones = zones;
        _loadingZones = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingZones = false);
    }
  }

  DeliveryZone? _zoneById(String id) {
    for (final zone in _zones) {
      if (zone.id == id) return zone;
    }
    return null;
  }

  void _selectZone(String id) {
    setState(() => _zoneId = id);
    final zone = _zoneById(id);
    if (zone != null && _address.text.trim().isEmpty) {
      _address.text = '${zone.displayGovernorate}، ${zone.displayName}';
    }
  }

  Future<void> _save({bool printTicket = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final auth = AdminAuthService.instance;
      final updated = await ApiService.instance.updateDeliveryContact(
        widget.order.id,
        address: _address.text.trim(),
        phone: _phone.text.trim(),
        deliveryInstructions: _notes.text.trim(),
        deliveryZoneId: _zoneId,
        performedById: auth.auditUserId,
        performedByName: auth.auditUserName,
      );
      final saved = updated ?? widget.order;
      if (printTicket) {
        await PosPrintHelper.printOrder(
          order: saved,
          kind: PosReceiptKind.kitchen,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(updated ?? saved);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Widget _clearableField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _save(printTicket: true),
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'مسح',
                onPressed: controller.clear,
                icon: const Icon(Icons.clear),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _zoneById(_zoneId);
    return AlertDialog(
      title: const Text('منطقة التوصيل والعنوان'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_zones.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: ValueKey('zone-$_zoneId-${_zones.length}'),
                  initialValue: _zones.any((zone) => zone.id == _zoneId) ? _zoneId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'منطقة ألمينو'),
                  items: [
                    for (final zone in _zones)
                      DropdownMenuItem(
                        value: zone.id,
                        child: Text(
                          '${zone.displayGovernorate} — ${zone.displayName}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) _selectZone(value);
                        },
                ),
              const SizedBox(height: 8),
              if (_loadingZones)
                const LinearProgressIndicator(minHeight: 2)
              else if (_zones.isEmpty)
                const Text(
                  'لا توجد مناطق توصيل محفوظة',
                  style: TextStyle(color: Color(0xFF64748B)),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 148),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final zone in _zones)
                          ChoiceChip(
                            label: Text(zone.displayName),
                            selected: zone.id == _zoneId,
                            onSelected: _saving
                                ? null
                                : (selected) => _selectZone(selected ? zone.id : ''),
                          ),
                      ],
                    ),
                  ),
                ),
              if (selected != null) ...[
                const SizedBox(height: 8),
                Text(
                  'التذكرة ستذهب لمطبخ هذه المنطقة، والطلب يظهر لسائقيها. مبلغ المنصة لا يتغير.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
              const SizedBox(height: 12),
              _clearableField(controller: _address, label: 'العنوان'),
              const SizedBox(height: 8),
              _clearableField(
                controller: _phone,
                label: 'الهاتف',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 8),
              _clearableField(controller: _notes, label: 'تعليمات التوصيل'),
              const SizedBox(height: 8),
              const Text(
                'Enter يحفظ المنطقة ويطبع تذكرة المطبخ',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _saving ? null : () => _save(printTicket: true),
          child: Text(_saving ? 'جاري الحفظ…' : 'حفظ وطباعة'),
        ),
      ],
    );
  }
}

class _PlatformSettlementEditor extends StatefulWidget {
  const _PlatformSettlementEditor({
    required this.order,
    required this.onUpdated,
  });

  final Order order;
  final ValueChanged<Order> onUpdated;

  @override
  State<_PlatformSettlementEditor> createState() =>
      _PlatformSettlementEditorState();
}

class _PlatformSettlementEditorState extends State<_PlatformSettlementEditor> {
  late final TextEditingController _amount;
  String? _method;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.order.customerPayable.toStringAsFixed(3),
    );
    _method = _methodOf(widget.order.paymentMethod);
  }

  @override
  void didUpdateWidget(covariant _PlatformSettlementEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.customerPayable != widget.order.customerPayable ||
        oldWidget.order.paymentMethod != widget.order.paymentMethod) {
      _amount.text = widget.order.customerPayable.toStringAsFixed(3);
      _method = _methodOf(widget.order.paymentMethod);
    }
  }

  String? _methodOf(String? value) {
    final text = (value ?? '').toLowerCase();
    if (text.contains('knet') || text.contains('k-net') || text.contains('كي')) {
      return 'KNET';
    }
    if (text.contains('cash') ||
        text.contains('cod') ||
        text.contains('كاش') ||
        text.contains('نقد')) {
      return 'Cash';
    }
    return null;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final method = _method;
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    if (method == null || amount == null || amount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر كاش أو كي نت واكتب مبلغ الفاتورة')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final auth = AdminAuthService.instance;
      final updated = await ApiService.instance.correctPlatformSettlement(
        widget.order.id,
        paymentMethod: method,
        invoiceAmount: amount,
        performedById: auth.auditUserId,
        performedByName: auth.auditUserName,
      );
      if (!mounted) return;
      if (updated != null) {
        OrdersDemoService.applyServerOrder(updated);
        widget.onUpdated(updated);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تصحيح الدفع ومبلغ الفاتورة')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'تصحيح السحب: كاش أو كي نت، ومبلغ الفاتورة. السحب التالي لا يرجع يغيّرهما.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('كاش'),
                selected: _method == 'Cash',
                onSelected: _saving ? null : (_) => setState(() => _method = 'Cash'),
              ),
              ChoiceChip(
                label: const Text('كي نت'),
                selected: _method == 'KNET',
                onSelected: _saving ? null : (_) => setState(() => _method = 'KNET'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'مبلغ الفاتورة',
              suffixText: 'د.ك',
              isDense: true,
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'جاري الحفظ…' : 'حفظ التصحيح'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaTile extends StatelessWidget {
  const _MetaTile({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
                    fontSize: highlight ? 15 : 13,
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

class _OrderItemTile extends StatelessWidget {
  const _OrderItemTile(this.item);

  final OrderLineItem item;

  @override
  Widget build(BuildContext context) {
    final addons = item.selectedOptions
        .map((option) => '+ ${option.group}: ${option.name}')
        .join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF6B1124).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${item.quantity}x',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6B1124),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${item.lineTotal.toStringAsFixed(3)} د.ك',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (addons.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(addons, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          ],
          if (item.specialNotes?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 6),
            Text(
              '⚠ ${item.specialNotes!.trim()}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFB45309),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrderStatusTimelineCard extends StatelessWidget {
  const _OrderStatusTimelineCard({required this.order});

  final Order order;

  static const _steps = [
    ('accepted_at', 'تم القبول'),
    ('driver_assigned_at', 'في الطريق للمطعم'),
    ('picked_up_at', 'تم الاستلام'),
    ('on_the_way_at', 'في الطريق للعميل'),
    ('delivered_at', 'تم التوصيل'),
  ];

  @override
  Widget build(BuildContext context) {
    final timeline = order.statusTimeline.createdAt == null
        ? order.statusTimeline.stamp('created_at', order.createdAt)
        : order.statusTimeline;
    final timeFormat = DateFormat('hh:mm a');
    final durations = <String>[];
    final prep = timeline.preparationDuration;
    if (prep != null && !prep.isNegative) {
      durations.add('وقت التحضير: ${_formatDuration(prep)}');
    }
    final delivery = timeline.deliveryDuration;
    if (delivery != null && !delivery.isNegative) {
      durations.add('وقت التوصيل: ${_formatDuration(delivery)}');
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8D5CE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'مسار الطلب',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _steps.length; i++) ...[
            _TimelineStep(
              label: _steps[i].$2,
              time: timeline.timeFor(_steps[i].$1),
              format: timeFormat,
              showConnector: i < _steps.length - 1,
            ),
          ],
          if (durations.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final text in durations)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6B1124).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B1124),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes <= 0) return '${duration.inSeconds} ث';
    if (minutes < 60) return '$minutes د';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours س' : '$hours س $rest د';
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.label,
    required this.time,
    required this.format,
    this.showConnector = false,
  });

  final String label;
  final DateTime? time;
  final DateFormat format;
  final bool showConnector;

  @override
  Widget build(BuildContext context) {
    final done = time != null;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? const Color(0xFF2E7D32) : Colors.white,
                  border: Border.all(
                    color: done ? const Color(0xFF2E7D32) : const Color(0xFFBCAAA4),
                    width: 2,
                  ),
                ),
                child: done
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              if (showConnector)
                Expanded(
                  child: Container(
                    width: 2,
                    color: done ? const Color(0xFF2E7D32) : const Color(0xFFD7CCC8),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: showConnector ? 12 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: done ? const Color(0xFF1B1B1B) : const Color(0xFF8D6E63),
                    ),
                  ),
                  Text(
                    done ? format.format(time!.toLocal()) : '—',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: done ? const Color(0xFF6B1124) : const Color(0xFFBCAAA4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.muted = false,
    this.color,
  });

  final String label;
  final String value;
  final bool bold;
  final bool muted;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                color: muted ? const Color(0xFF64748B) : null,
              ),
            ),
          ),
          Text(
            '$value د.ك',
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: color ?? (muted ? const Color(0xFF64748B) : null),
            ),
          ),
        ],
      ),
    );
  }
}
