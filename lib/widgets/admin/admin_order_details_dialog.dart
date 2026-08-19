import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/order.dart';
import '../../models/sales_platform_config.dart';
import '../../services/admin_auth_service.dart';
import '../../services/restaurant_settings_service.dart';
import '../../utils/pos_receipt_html.dart';
import 'pos/pos_print_preview_dialog.dart';

Future<void> showAdminOrderDetailsDialog(
  BuildContext context, {
  required Order order,
  required List<SalesPlatformConfig> platforms,
  required Future<void> Function(String orderId, OrderStatus status) onStatusChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AdminOrderDetailsDialog(
      order: order,
      platforms: platforms,
      onStatusChanged: onStatusChanged,
    ),
  );
}

class AdminOrderDetailsDialog extends StatelessWidget {
  const AdminOrderDetailsDialog({
    super.key,
    required this.order,
    required this.platforms,
    required this.onStatusChanged,
  });

  final Order order;
  final List<SalesPlatformConfig> platforms;
  final Future<void> Function(String orderId, OrderStatus status) onStatusChanged;

  SalesPlatformConfig get _platform =>
      PlatformCatalog.resolve(order.orderSource, platforms);

  bool get _showAddressDetails => _platform.isLocal;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d/M/yyyy • HH:mm');
    final orderId = order.invoiceNumber ?? order.id;
    final nextStatus = order.status.nextStatus;
    final nextLabel = order.status.nextActionLabel;
    final restaurantName =
        AdminAuthService.instance.restaurantName ?? 'المطعم';

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
                    if (_showAddressDetails) ...[
                      _MetaTile(
                        icon: Icons.location_on_outlined,
                        label: 'العنوان',
                        value: order.address,
                      ),
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
                    _MetaTile(
                      icon: Icons.payment_outlined,
                      label: 'الدفع',
                      value: order.paymentMethod ?? 'غير محدد',
                    ),
                    _MetaTile(
                      icon: Icons.local_shipping_outlined,
                      label: 'النوع',
                      value: order.orderType == OrderType.pickup ? 'استلام' : 'توصيل',
                    ),
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
                            label: 'الإجمالي',
                            value: order.totalPrice.toStringAsFixed(3),
                            bold: true,
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
                            final settings =
                                await RestaurantSettingsService.instance.load();
                            if (!context.mounted) return;
                            await showPosPrintPreviewDialog(
                              context,
                              order: order,
                              restaurantName: restaurantName,
                              kind: PosReceiptKind.kitchen,
                              restaurantPhone: settings.fullWhatsappNumber,
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
                            final settings =
                                await RestaurantSettingsService.instance.load();
                            if (!context.mounted) return;
                            await showPosPrintPreviewDialog(
                              context,
                              order: order,
                              restaurantName: restaurantName,
                              kind: PosReceiptKind.customer,
                              restaurantPhone: settings.fullWhatsappNumber,
                            );
                          },
                          icon: const Icon(Icons.receipt_long, size: 18),
                          label: const Text('طباعة فاتورة'),
                        ),
                      ),
                    ],
                  ),
                  if (nextStatus != null && nextLabel != null) ...[
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
