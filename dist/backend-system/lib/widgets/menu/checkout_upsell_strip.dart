import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/upsell_recommendation.dart';
import '../../services/upsell_analytics_service.dart';
import '../../theme/app_theme.dart';
import '../network_menu_image.dart';

/// Shared horizontal upsell strip — used for smart recommendations and impulse bumps.
class CheckoutUpsellStrip extends StatefulWidget {
  const CheckoutUpsellStrip({
    super.key,
    required this.title,
    this.subtitle,
    required this.recommendations,
    required this.localeCode,
    required this.strings,
    required this.onAddItem,
    required this.surface,
    this.restaurantSlug,
    this.restaurantId,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final List<UpsellRecommendation> recommendations;
  final String localeCode;
  final AppStrings strings;
  final ValueChanged<UpsellRecommendation> onAddItem;
  final String surface;
  final String? restaurantSlug;
  final String? restaurantId;
  final bool compact;

  @override
  State<CheckoutUpsellStrip> createState() => _CheckoutUpsellStripState();
}

class _CheckoutUpsellStripState extends State<CheckoutUpsellStrip> {
  @override
  void initState() {
    super.initState();
    _trackImpressions();
  }

  @override
  void didUpdateWidget(covariant CheckoutUpsellStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recommendations != widget.recommendations ||
        oldWidget.surface != widget.surface) {
      _trackImpressions();
    }
  }

  void _trackImpressions() {
    UpsellAnalyticsService.instance.logImpressions(
      surface: widget.surface,
      recommendations: widget.recommendations,
      slug: widget.restaurantSlug,
      restaurantId: widget.restaurantId,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.recommendations.isEmpty) return const SizedBox.shrink();

    final cardWidth = widget.compact ? 128.0 : 148.0;
    final stripHeight = widget.compact ? 168.0 : 188.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.brandOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  widget.compact ? Icons.bolt : Icons.auto_awesome,
                  color: AppTheme.brandOrange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.brandMaroon,
                      ),
                    ),
                    if (widget.subtitle != null &&
                        widget.subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: stripHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: widget.recommendations.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final recommendation = widget.recommendations[index];
              return _UpsellCard(
                recommendation: recommendation,
                localeCode: widget.localeCode,
                strings: widget.strings,
                width: cardWidth,
                compact: widget.compact,
                onAdd: () => widget.onAddItem(recommendation),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _UpsellCard extends StatelessWidget {
  const _UpsellCard({
    required this.recommendation,
    required this.localeCode,
    required this.strings,
    required this.width,
    required this.compact,
    required this.onAdd,
  });

  final UpsellRecommendation recommendation;
  final String localeCode;
  final AppStrings strings;
  final double width;
  final bool compact;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final item = recommendation.item;
    final name = item.localizedName(localeCode);
    final reason = recommendation.reasonLabel(localeCode);

    return Material(
      elevation: 1,
      shadowColor: AppTheme.brandMaroon.withValues(alpha: 0.12),
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onAdd,
        child: Container(
          width: width,
          decoration: BoxDecoration(
            border: Border.all(
              color: AppTheme.brandMaroon.withValues(alpha: 0.1),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: compact ? 3 : 4,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.imageUrl.isNotEmpty)
                      NetworkMenuImage(
                        imageUrl: item.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(),
                      )
                    else
                      _placeholder(),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.brandMaroon.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          reason,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Material(
                        color: AppTheme.brandOrange,
                        shape: const CircleBorder(),
                        elevation: 3,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onAdd,
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${item.price.toStringAsFixed(3)} ${strings.currency}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.brandMaroon,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          strings.quickAddLabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.brandOrange.withValues(alpha: 0.95),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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

  Widget _placeholder() {
    return Container(
      color: AppTheme.brandMaroon.withValues(alpha: 0.06),
      child: const Icon(Icons.restaurant, color: AppTheme.brandMaroon),
    );
  }
}
