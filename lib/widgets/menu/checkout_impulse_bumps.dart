import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/menu_item.dart';
import '../../models/upsell_recommendation.dart';
import 'checkout_upsell_strip.dart';

class CheckoutImpulseBumps extends StatelessWidget {
  const CheckoutImpulseBumps({
    super.key,
    required this.recommendations,
    required this.localeCode,
    required this.strings,
    required this.onAddItem,
    this.freeDeliveryHint,
  });

  /// Legacy constructor accepting flat [MenuItem] list.
  factory CheckoutImpulseBumps.fromItems({
    required List<MenuItem> items,
    required String localeCode,
    required AppStrings strings,
    required ValueChanged<MenuItem> onAddItem,
    String? freeDeliveryHint,
  }) {
    return CheckoutImpulseBumps(
      recommendations: items
          .map(
            (item) => UpsellRecommendation(
              item: item,
              reason: UpsellReason.impulse,
            ),
          )
          .toList(),
      localeCode: localeCode,
      strings: strings,
      onAddItem: (entry) => onAddItem(entry.item),
      freeDeliveryHint: freeDeliveryHint,
    );
  }

  final List<UpsellRecommendation> recommendations;
  final String localeCode;
  final AppStrings strings;
  final ValueChanged<UpsellRecommendation> onAddItem;
  final String? freeDeliveryHint;

  @override
  Widget build(BuildContext context) {
    return CheckoutUpsellStrip(
      title: strings.impulseBumpsTitle,
      subtitle: freeDeliveryHint ?? strings.impulseBumpsSubtitle,
      recommendations: recommendations,
      localeCode: localeCode,
      strings: strings,
      onAddItem: onAddItem,
      compact: true,
    );
  }
}
