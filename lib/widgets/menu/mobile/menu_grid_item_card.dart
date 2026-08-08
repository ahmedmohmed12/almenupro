import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/app_strings.dart';
import '../../../models/menu_item.dart';
import '../../../theme/app_theme.dart';
import '../../network_menu_image.dart';

class MenuGridItemCard extends StatelessWidget {
  const MenuGridItemCard({
    super.key,
    required this.item,
    required this.localeCode,
    required this.strings,
    required this.onAdd,
  });

  final MenuItem item;
  final String localeCode;
  final AppStrings strings;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final name = item.localizedName(localeCode);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onAdd,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.brandMaroon.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _ItemImage(imageUrl: item.imageUrl),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _AddButton(onPressed: onAdd),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.brandBlack,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.price.toStringAsFixed(3)} ${strings.currency}',
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.brandMaroon,
                      ),
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

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.brandOrange,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const SizedBox(
          width: 34,
          height: 34,
          child: Icon(Icons.add, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _ItemImage extends StatelessWidget {
  const _ItemImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isEmpty) {
      return Container(
        color: AppTheme.brandSurface,
        alignment: Alignment.center,
        child: const Icon(Icons.restaurant, color: AppTheme.brandOrange, size: 40),
      );
    }

    return NetworkMenuImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: AppTheme.brandSurface,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image, color: AppTheme.brandOrange),
      ),
    );
  }
}
