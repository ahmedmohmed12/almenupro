import 'package:flutter/material.dart';

import '../../models/menu_item.dart';
import '../../theme/app_theme.dart';

class ProductDiscountBadge extends StatelessWidget {
  const ProductDiscountBadge({
    super.key,
    required this.percent,
    this.compact = false,
  });

  final int percent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE11D48),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 2 : 4,
        ),
        child: Text(
          '-$percent%',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: compact ? 11 : 12.5,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

class ProductSalePrice extends StatelessWidget {
  const ProductSalePrice({
    super.key,
    required this.item,
    this.compact = false,
    this.currency = 'د.ك',
  });

  final MenuItem item;
  final bool compact;
  final String currency;

  @override
  Widget build(BuildContext context) {
    if (!item.hasDiscount) return const SizedBox.shrink();
    final original = item.originalPrice!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '${original.toStringAsFixed(3)} $currency',
          style: TextStyle(
            fontSize: compact ? 10 : 11,
            color: const Color(0xFF94A3B8),
            decoration: TextDecoration.lineThrough,
            decorationColor: const Color(0xFF94A3B8),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '${item.finalPrice.toStringAsFixed(3)} $currency',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 13 : 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.brandOrange,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}
