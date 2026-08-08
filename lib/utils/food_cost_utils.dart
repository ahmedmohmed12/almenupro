import 'package:flutter/material.dart';

enum FoodCostLevel { low, medium, high, unknown }

class FoodCostMetrics {
  const FoodCostMetrics({
    required this.sellingPrice,
    this.costPrice,
  });

  final double sellingPrice;
  final double? costPrice;

  double? get profitMargin {
    if (costPrice == null || sellingPrice <= 0) return null;
    return ((sellingPrice - costPrice!) / sellingPrice) * 100;
  }

  double? get foodCostPercent {
    if (costPrice == null || sellingPrice <= 0) return null;
    return (costPrice! / sellingPrice) * 100;
  }

  FoodCostLevel get level {
    final percent = foodCostPercent;
    if (percent == null) return FoodCostLevel.unknown;
    if (percent < 30) return FoodCostLevel.low;
    if (percent <= 40) return FoodCostLevel.medium;
    return FoodCostLevel.high;
  }

  static FoodCostMetrics? fromPrices({
    required double? sellingPrice,
    required double? costPrice,
  }) {
    if (sellingPrice == null || sellingPrice <= 0) return null;
    if (costPrice == null || costPrice < 0) {
      return FoodCostMetrics(sellingPrice: sellingPrice);
    }
    return FoodCostMetrics(sellingPrice: sellingPrice, costPrice: costPrice);
  }

  static double? parseCostPrice(Map<String, dynamic> map) {
    final raw = map['costPrice'] ?? map['cost_price'];
    if (raw == null || raw == '') return null;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString());
  }
}

class FoodCostBadge extends StatelessWidget {
  const FoodCostBadge({
    super.key,
    required this.sellingPrice,
    this.costPrice,
    this.compact = false,
  });

  final double sellingPrice;
  final double? costPrice;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final metrics = FoodCostMetrics.fromPrices(
      sellingPrice: sellingPrice,
      costPrice: costPrice,
    );

    if (metrics == null || metrics.foodCostPercent == null) {
      return const SizedBox.shrink();
    }

    final percent = metrics.foodCostPercent!;
    final margin = metrics.profitMargin;
    final (color, label) = _styleForLevel(metrics.level);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.pie_chart_outline, size: compact ? 14 : 16, color: color),
          const SizedBox(width: 6),
          Text(
            compact
                ? 'تكلفة ${percent.toStringAsFixed(1)}%'
                : 'تكلفة الطعام ${percent.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          if (margin != null) ...[
            const SizedBox(width: 8),
            Text(
              'هامش ${margin.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: compact ? 11 : 12, color: color),
            ),
          ],
        ],
      ),
    );
  }

  (Color, String) _styleForLevel(FoodCostLevel level) {
    switch (level) {
      case FoodCostLevel.low:
        return (const Color(0xFF2E7D32), 'منخفضة');
      case FoodCostLevel.medium:
        return (const Color(0xFFF9A825), 'متوسطة');
      case FoodCostLevel.high:
        return (const Color(0xFFC62828), 'مرتفعة');
      case FoodCostLevel.unknown:
        return (const Color(0xFF757575), 'غير محددة');
    }
  }
}

class FoodCostBadgeRow extends StatelessWidget {
  const FoodCostBadgeRow({
    super.key,
    required this.sellingPrice,
    required this.costPriceText,
    required this.onCostPriceChanged,
  });

  final double sellingPrice;
  final String costPriceText;
  final ValueChanged<String> onCostPriceChanged;

  @override
  Widget build(BuildContext context) {
    final costPrice = double.tryParse(costPriceText.trim());
    final parsedCost =
        costPrice != null && costPrice >= 0 ? costPrice : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'تكلفة المكونات (د.ك) — اختياري',
            helperText: 'تُستخدم لحساب هامش الربح وترتيب اقتراحات البياع الشاطر',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          controller: TextEditingController(text: costPriceText)
            ..selection = TextSelection.collapsed(offset: costPriceText.length),
          onChanged: onCostPriceChanged,
        ),
        if (parsedCost != null && sellingPrice > 0) ...[
          const SizedBox(height: 8),
          FoodCostBadge(sellingPrice: sellingPrice, costPrice: parsedCost),
        ],
      ],
    );
  }
}
