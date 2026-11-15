import 'package:flutter/material.dart';

/// Sales channel for an order (POS local vs delivery platforms).
enum OrderPlatform {
  posLocal,
  talabat,
  keeta,
  jahez,
  other;

  String get storageKey {
    switch (this) {
      case OrderPlatform.posLocal:
        return 'pos';
      case OrderPlatform.talabat:
        return 'talabat';
      case OrderPlatform.keeta:
        return 'keeta';
      case OrderPlatform.jahez:
        return 'jahez';
      case OrderPlatform.other:
        return 'other_platform';
    }
  }

  String get arabicLabel {
    switch (this) {
      case OrderPlatform.posLocal:
        return 'محلي / POS';
      case OrderPlatform.talabat:
        return 'Talabat';
      case OrderPlatform.keeta:
        return 'Keeta';
      case OrderPlatform.jahez:
        return 'Jahez';
      case OrderPlatform.other:
        return 'منصة أخرى';
    }
  }

  IconData get icon {
    switch (this) {
      case OrderPlatform.posLocal:
        return Icons.storefront_rounded;
      case OrderPlatform.talabat:
        return Icons.delivery_dining_rounded;
      case OrderPlatform.keeta:
        return Icons.two_wheeler_rounded;
      case OrderPlatform.jahez:
        return Icons.moped_rounded;
      case OrderPlatform.other:
        return Icons.hub_rounded;
    }
  }

  Color get color {
    switch (this) {
      case OrderPlatform.posLocal:
        return const Color(0xFF6B1124);
      case OrderPlatform.talabat:
        return const Color(0xFFFF5A00);
      case OrderPlatform.keeta:
        return const Color(0xFF00A651);
      case OrderPlatform.jahez:
        return const Color(0xFFE4002B);
      case OrderPlatform.other:
        return const Color(0xFF475569);
    }
  }

  double get defaultCommissionPercent {
    switch (this) {
      case OrderPlatform.posLocal:
        return 0;
      case OrderPlatform.talabat:
        return 15;
      case OrderPlatform.keeta:
        return 12;
      case OrderPlatform.jahez:
        return 12;
      case OrderPlatform.other:
        return 10;
    }
  }

  bool get isExternal => this != OrderPlatform.posLocal;

  static OrderPlatform fromStorage(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    switch (value) {
      case 'talabat':
        return OrderPlatform.talabat;
      case 'keeta':
        return OrderPlatform.keeta;
      case 'jahez':
        return OrderPlatform.jahez;
      case 'other_platform':
      case 'other':
        return OrderPlatform.other;
      case 'pos':
      case 'menu':
      case 'whatsapp':
      default:
        return OrderPlatform.posLocal;
    }
  }
}

class PlatformOrderMeta {
  const PlatformOrderMeta({
    this.externalOrderId,
    this.platformGrossTotal,
    this.platformCommission,
    this.platformCommissionPercent,
  });

  final String? externalOrderId;
  final double? platformGrossTotal;
  final double? platformCommission;
  final double? platformCommissionPercent;

  double netRevenue(double orderTotal) {
    if (platformCommission != null && platformCommission! > 0) {
      return (orderTotal - platformCommission!).clamp(0, double.infinity);
    }
    if (platformGrossTotal != null && platformGrossTotal! > 0) {
      return platformGrossTotal!.clamp(0, double.infinity);
    }
    return orderTotal;
  }

  Map<String, dynamic> toMap() => {
        if (externalOrderId != null && externalOrderId!.isNotEmpty)
          'externalOrderId': externalOrderId,
        if (platformGrossTotal != null) 'platformGrossTotal': platformGrossTotal,
        if (platformCommission != null) 'platformCommission': platformCommission,
        if (platformCommissionPercent != null)
          'platformCommissionPercent': platformCommissionPercent,
      };

  factory PlatformOrderMeta.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const PlatformOrderMeta();
    return PlatformOrderMeta(
      externalOrderId: map['externalOrderId']?.toString() ??
          map['external_order_id']?.toString(),
      platformGrossTotal: (map['platformGrossTotal'] as num?)?.toDouble() ??
          (map['platform_gross_total'] as num?)?.toDouble(),
      platformCommission: (map['platformCommission'] as num?)?.toDouble() ??
          (map['platform_commission'] as num?)?.toDouble(),
      platformCommissionPercent:
          (map['platformCommissionPercent'] as num?)?.toDouble() ??
              (map['platform_commission_percent'] as num?)?.toDouble(),
    );
  }
}

class OrderPlatformBadge extends StatelessWidget {
  const OrderPlatformBadge({
    super.key,
    required this.platform,
    this.compact = false,
  });

  final OrderPlatform platform;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: platform.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        border: Border.all(color: platform.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(platform.icon, size: compact ? 12 : 14, color: platform.color),
          if (!compact) ...[
            const SizedBox(width: 4),
            Text(
              platform.arabicLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: platform.color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

OrderPlatform platformFromOrderSource(String? source) =>
    OrderPlatform.fromStorage(source);
