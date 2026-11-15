import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/menu_item.dart';
import '../../theme/app_theme.dart';
import '../network_menu_image.dart';

class TableQrItemCard extends StatelessWidget {
  const TableQrItemCard({
    super.key,
    required this.item,
    required this.onOpenDetails,
    required this.onQuickAdd,
  });

  final MenuItem item;
  final VoidCallback onOpenDetails;
  final VoidCallback onQuickAdd;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.read(context);
    final locale = strings.localeCode;
    final title = item.localizedName(locale);
    final description = item.localizedDescription(locale);
    final priceLabel = '${item.price.toStringAsFixed(2)} ${strings.currency}';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onOpenDetails,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.brandMaroon.withValues(alpha: 0.1),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 88,
                    height: 88,
                    child: item.imageUrl.trim().isEmpty
                        ? Container(
                            color: AppTheme.brandSurface,
                            child: const Icon(
                              Icons.restaurant,
                              color: AppTheme.brandMaroon,
                            ),
                          )
                        : NetworkMenuImage(
                            imageUrl: item.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: AppTheme.brandSurface,
                              child: const Icon(
                                Icons.restaurant,
                                color: AppTheme.brandMaroon,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (description.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            priceLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.brandOrange,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          Material(
                            color: AppTheme.brandOrange,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              onTap: onQuickAdd,
                              borderRadius: BorderRadius.circular(10),
                              child: const SizedBox(
                                width: 36,
                                height: 36,
                                child: Icon(
                                  Icons.add,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
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
      ),
    );
  }
}
