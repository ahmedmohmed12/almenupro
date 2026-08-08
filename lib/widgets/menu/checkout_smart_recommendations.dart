import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/upsell_recommendation.dart';
import 'checkout_upsell_strip.dart';

class CheckoutSmartRecommendations extends StatelessWidget {
  const CheckoutSmartRecommendations({
    super.key,
    required this.recommendations,
    required this.localeCode,
    required this.strings,
    required this.onAddItem,
  });

  final List<UpsellRecommendation> recommendations;
  final String localeCode;
  final AppStrings strings;
  final ValueChanged<UpsellRecommendation> onAddItem;

  @override
  Widget build(BuildContext context) {
    return CheckoutUpsellStrip(
      title: strings.smartRecommendationsTitle,
      subtitle: strings.smartRecommendationsSubtitle,
      recommendations: recommendations,
      localeCode: localeCode,
      strings: strings,
      onAddItem: onAddItem,
    );
  }
}
