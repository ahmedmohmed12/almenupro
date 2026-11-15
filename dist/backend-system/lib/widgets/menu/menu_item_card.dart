import 'package:flutter/material.dart';

import '../../models/menu_item.dart';
import '../../theme/app_theme.dart';
import '../network_menu_image.dart';
import 'product_sale_price.dart';

class MenuItemCard extends StatelessWidget {
  const MenuItemCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  final MenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  item.imageUrl.isNotEmpty
                      ? NetworkMenuImage(
                          imageUrl: item.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const _ImageFallback(),
                        )
                      : const _ImageFallback(),
                  if (item.hasDiscount && item.discountPercent != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: ProductDiscountBadge(percent: item.discountPercent!),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        if (item.hasDiscount)
                          Expanded(
                            child: ProductSalePrice(item: item, currency: '\$'),
                          )
                        else
                          Text(
                            '\$${item.price.toStringAsFixed(2)}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: AppTheme.brandPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        if (item.options.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            'Customizable',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Icon(
                          Icons.add_circle,
                          color: AppTheme.brandPrimary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.grey.shade100,
      child: const Center(
        child: Icon(Icons.restaurant, size: 40, color: Colors.grey),
      ),
    );
  }
}
