import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../network_menu_image.dart';

class TableQrHeader extends StatelessWidget {
  const TableQrHeader({
    super.key,
    required this.restaurantName,
    required this.logoUrl,
    required this.tableLabel,
    required this.zoneLabel,
    required this.onCallWaiter,
    this.busy = false,
  });

  final String restaurantName;
  final String logoUrl;
  final String tableLabel;
  final String zoneLabel;
  final VoidCallback onCallWaiter;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final badgeText = zoneLabel.trim().isEmpty
        ? tableLabel
        : '$tableLabel - $zoneLabel';

    return Material(
      color: Colors.white,
      elevation: 0.5,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              _Logo(url: logoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurantName.isEmpty ? 'AlMenuPro' : restaurantName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.brandBlack,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.brandOrange.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppTheme.brandOrange.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        badgeText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.brandMaroon,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: busy ? null : onCallWaiter,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE8F1FF),
                  foregroundColor: const Color(0xFF1D4ED8),
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.notifications_active_outlined, size: 18),
                label: const Text(
                  'نداء الويتر',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 48,
        height: 48,
        color: AppTheme.brandSurface,
        child: url.trim().isEmpty
            ? const Icon(Icons.storefront, color: AppTheme.brandMaroon)
            : NetworkMenuImage(
                imageUrl: url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.storefront, color: AppTheme.brandMaroon),
              ),
      ),
    );
  }
}
