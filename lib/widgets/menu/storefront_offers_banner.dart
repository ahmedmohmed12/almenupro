import 'package:flutter/material.dart';

import '../../models/offer.dart';
import '../../theme/app_theme.dart';
import '../network_menu_image.dart';

class StorefrontOffersBanner extends StatelessWidget {
  const StorefrontOffersBanner({
    super.key,
    required this.offers,
    required this.onAdd,
  });

  final List<Offer> offers;
  final ValueChanged<Offer> onAdd;

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
            height: wide ? 156 : 132,
            child: PageView.builder(
              controller: PageController(viewportFraction: wide ? 0.68 : 0.94),
              itemCount: offers.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: StorefrontOfferCard(
                    offer: offers[index],
                    compact: !wide,
                    onAdd: () => onAdd(offers[index]),
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
    required this.onAdd,
    this.compact = false,
  });

  final Offer offer;
  final VoidCallback onAdd;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sale = offer.salePrice;
    final list = offer.listPrice;

    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppTheme.brandMaroon.withValues(alpha: 0.12)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onAdd,
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
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Row(
                      children: [
                        if (list > 0 && sale > 0 && sale < list) ...[
                          Text(
                            '${list.toStringAsFixed(3)} د.ك',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              decoration: TextDecoration.lineThrough,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (sale > 0)
                          Text(
                            '${sale.toStringAsFixed(3)} د.ك',
                            style: const TextStyle(
                              color: AppTheme.brandMaroon,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        else if (offer.type == OfferType.percentage)
                          Text(
                            'خصم ${offer.discountValue.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: AppTheme.brandMaroon,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        const Spacer(),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.brandMaroon,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            minimumSize: const Size(0, 36),
                          ),
                          onPressed: onAdd,
                          child: const Text('أضف للسلة'),
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
}
