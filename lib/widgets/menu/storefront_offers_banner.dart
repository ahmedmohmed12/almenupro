import 'package:flutter/material.dart';

import '../../models/offer.dart';
import '../../theme/app_theme.dart';
import '../network_menu_image.dart';

class StorefrontOffersBanner extends StatelessWidget {
  const StorefrontOffersBanner({
    super.key,
    required this.offers,
    this.onOpenOffers,
  });

  final List<Offer> offers;
  final VoidCallback? onOpenOffers;

  @override
  Widget build(BuildContext context) {
    if (offers.isEmpty) return const SizedBox.shrink();
    final wide = MediaQuery.sizeOf(context).width >= 720;

    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 20 : 10, 6, wide ? 20 : 10, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'العروض والخصومات',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppTheme.brandMaroon,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: wide ? 148 : 124,
            child: PageView.builder(
              controller: PageController(viewportFraction: wide ? 0.68 : 0.94),
              itemCount: offers.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: StorefrontOfferCard(
                    offer: offers[index],
                    compact: !wide,
                    onTap: onOpenOffers,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class StorefrontOfferCard extends StatelessWidget {
  const StorefrontOfferCard({
    super.key,
    required this.offer,
    this.onTap,
    this.compact = false,
  });

  final Offer offer;
  final VoidCallback? onTap;
  final bool compact;

  String? get _terms {
    final parts = <String>[];
    if (offer.minSubtotal > 0) {
      parts.add('الحد الأدنى ${offer.minSubtotal.toStringAsFixed(3)} د.ك');
    }
    if (offer.hasUsageCap) {
      parts.add('حتى ${offer.usageLimitPerCustomer} مرة لكل عميل');
    }
    if (offer.endsAt != null) {
      final end = offer.endsAt!.toLocal();
      parts.add(
        'حتى ${end.year}/${end.month.toString().padLeft(2, '0')}/${end.day.toString().padLeft(2, '0')}',
      );
    }
    if (parts.isEmpty && offer.description.trim().isEmpty) return null;
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final terms = _terms;

    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppTheme.brandMaroon.withValues(alpha: 0.12)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 8 : 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: compact ? 64 : 84,
                  height: compact ? 88 : 108,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: const Color(0xFFFFF4E5),
                        child: offer.imageUrl.isEmpty
                            ? const Icon(
                                Icons.local_offer_outlined,
                                color: AppTheme.brandMaroon,
                                size: 32,
                              )
                            : NetworkMenuImage(imageUrl: offer.imageUrl),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.brandOrange,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            offer.displayBadge,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      offer.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: compact ? 13 : 15,
                        height: 1.25,
                      ),
                    ),
                    if (offer.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        offer.description,
                        maxLines: compact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (offer.type == OfferType.percentage)
                      Text(
                        'خصم ${offer.discountValue.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: AppTheme.brandMaroon,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    else if (offer.type == OfferType.fixed)
                      Text(
                        'خصم ${offer.discountValue.toStringAsFixed(3)} د.ك',
                        style: const TextStyle(
                          color: AppTheme.brandMaroon,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    else if (offer.hasPricePair)
                      Text(
                        '${offer.salePrice.toStringAsFixed(3)} د.ك بدل ${offer.listPrice.toStringAsFixed(3)}',
                        style: const TextStyle(
                          color: AppTheme.brandMaroon,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    if (terms != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        terms,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
