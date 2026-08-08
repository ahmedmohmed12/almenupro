import 'package:flutter/material.dart';

import '../../models/order.dart';
import '../../theme/app_theme.dart';

class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _colors(status);

    return Chip(
      label: Text(_label(status)),
      backgroundColor: background,
      labelStyle: TextStyle(
        color: foreground,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  String _label(OrderStatus status) => status.arabicLabel;

  (Color, Color) _colors(OrderStatus status) {
    return switch (status) {
      OrderStatus.pending => (Colors.amber.shade100, Colors.amber.shade900),
      OrderStatus.confirmed => (Colors.blue.shade100, Colors.blue.shade900),
      OrderStatus.preparing => (Colors.orange.shade100, Colors.orange.shade900),
      OrderStatus.ready => (Colors.green.shade100, Colors.green.shade900),
      OrderStatus.delivered => (Colors.teal.shade100, Colors.teal.shade900),
      OrderStatus.cancelled => (Colors.red.shade100, Colors.red.shade900),
    };
  }
}

class OrderTypeBadge extends StatelessWidget {
  const OrderTypeBadge({super.key, required this.orderType});

  final OrderType orderType;

  @override
  Widget build(BuildContext context) {
    final isDelivery = orderType == OrderType.delivery;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDelivery
            ? AppTheme.brandOrange.withValues(alpha: 0.12)
            : AppTheme.brandMaroon.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDelivery ? Icons.delivery_dining : Icons.storefront,
            size: 14,
            color: isDelivery ? AppTheme.brandOrange : AppTheme.brandMaroon,
          ),
          const SizedBox(width: 4),
          Text(
            orderType.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDelivery ? AppTheme.brandOrange : AppTheme.brandMaroon,
            ),
          ),
        ],
      ),
    );
  }
}
