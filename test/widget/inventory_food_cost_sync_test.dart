import 'package:almenupro/utils/food_cost_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('food cost percent from AVCO-synced recipe cost', () {
    final metrics = FoodCostMetrics.fromPrices(sellingPrice: 2.5, costPrice: 0.75);
    expect(metrics, isNotNull);
    expect(metrics!.foodCostPercent, closeTo(30, 0.01));
    expect(metrics.profitMargin, closeTo(70, 0.01));
  });
}