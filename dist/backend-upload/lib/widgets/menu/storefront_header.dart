import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/menu_item.dart';
import '../../providers/customer_session_provider.dart';
import '../../providers/locale_provider.dart';
import '../../theme/app_theme.dart';
import '../network_menu_image.dart';
import 'product_sale_price.dart';
import 'menu_engineering_badge.dart';

class StorefrontHero extends StatelessWidget {
  const StorefrontHero({
    super.key,
    required this.restaurantName,
    required this.description,
    required this.logoUrl,
    required this.deliveryFee,
    required this.session,
    this.heroImageUrl = '',
    this.isArabic = true,
    this.rating,
    this.reviewCount = 0,
    this.onSearch,
    this.onShare,
    this.onToggleLanguage,
  });

  final String restaurantName;
  final String description;
  final String logoUrl;
  final double deliveryFee;
  final CustomerSessionProvider session;
  final String heroImageUrl;
  final bool isArabic;
  final double? rating;
  final int reviewCount;
  final VoidCallback? onSearch;
  final VoidCallback? onShare;
  final VoidCallback? onToggleLanguage;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width < 520;
        final desktop = width >= 900;
        final bannerHeight = desktop
            ? 280.0
            : compact
            ? 220.0
            : 248.0;
        final logoSize = desktop
            ? 64.0
            : compact
            ? 44.0
            : 52.0;
        final titleSize = desktop
            ? 22.0
            : compact
            ? 15.0
            : 17.0;
        final horizontal = desktop ? 20.0 : 10.0;
        final coverUrl = heroImageUrl.trim();

        return Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  height: bannerHeight,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _HeroBackdrop(
                        imageUrl: coverUrl,
                        cookieSize: desktop ? 96 : 64,
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x99000000),
                              Color(0x33000000),
                              Color(0x66000000),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        left: horizontal,
                        right: horizontal,
                        child: _HeroActions(
                          isArabic: isArabic,
                          onSearch: onSearch,
                          onShare: onShare,
                          onToggleLanguage: onToggleLanguage,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    bannerHeight - (compact ? 28 : 38),
                    horizontal,
                    0,
                  ),
                  child: Material(
                    color: Colors.white,
                    elevation: 6,
                    shadowColor: Colors.black26,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 10 : 12,
                        compact ? 8 : 10,
                        compact ? 10 : 12,
                        compact ? 8 : 10,
                      ),
                      child: compact
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _Logo(url: logoUrl, size: logoSize),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _Identity(
                                        restaurantName: restaurantName,
                                        description: description,
                                        titleSize: titleSize,
                                        maxDescriptionLines: 2,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                _MetaRow(
                                  deliveryFee: deliveryFee,
                                  isArabic: isArabic,
                                  rating: rating,
                                  reviewCount: reviewCount,
                                ),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Logo(url: logoUrl, size: logoSize),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _Identity(
                                        restaurantName: restaurantName,
                                        description: description,
                                        titleSize: titleSize,
                                        maxDescriptionLines: desktop ? 2 : 1,
                                      ),
                                      const SizedBox(height: 6),
                                      _MetaRow(
                                        deliveryFee: deliveryFee,
                                        isArabic: isArabic,
                                        rating: rating,
                                        reviewCount: reviewCount,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 0),
              child: _PromoBanner(session: session, compact: compact),
            ),
          ],
        );
      },
    );
  }
}

class _HeroBackdrop extends StatelessWidget {
  const _HeroBackdrop({required this.imageUrl, required this.cookieSize});

  final String imageUrl;
  final double cookieSize;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl.trim().isNotEmpty;
    return ColoredBox(
      color: const Color(0xFF6B1124),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF6B1124), Color(0xFFB45309)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
          ),
          if (hasImage)
            NetworkMenuImage(imageUrl: imageUrl, fit: BoxFit.cover)
          else
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Icon(
                  Icons.cookie,
                  color: Colors.white24,
                  size: cookieSize,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeroActions extends StatelessWidget {
  const _HeroActions({
    required this.isArabic,
    this.onSearch,
    this.onShare,
    this.onToggleLanguage,
  });

  final bool isArabic;
  final VoidCallback? onSearch;
  final VoidCallback? onShare;
  final VoidCallback? onToggleLanguage;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Spacer(),
        _CircleAction(
          icon: Icons.search,
          tooltip: isArabic ? 'بحث' : 'Search',
          onTap: onSearch,
        ),
        const SizedBox(width: 8),
        _CircleAction(
          icon: Icons.share_outlined,
          tooltip: isArabic ? 'مشاركة' : 'Share',
          onTap: onShare,
        ),
        const SizedBox(width: 8),
        _CircleAction(
          label: isArabic ? 'EN' : 'ع',
          tooltip: isArabic ? 'English' : 'العربية',
          onTap: onToggleLanguage,
        ),
      ],
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({this.icon, this.label, this.tooltip, this.onTap});

  final IconData? icon;
  final String? label;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: Colors.black.withValues(alpha: 0.38),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: label != null
                ? Text(
                    label!,
                    style: const TextStyle(
                      color: Color(0xFFF59E0B),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  )
                : Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
    if (tooltip == null || tooltip!.isEmpty) return child;
    return Tooltip(message: tooltip!, child: child);
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: size,
        height: size,
        child: url.trim().isEmpty
            ? const ColoredBox(
                color: Color(0xFFFFF4E5),
                child: Icon(Icons.storefront, color: AppTheme.brandMaroon),
              )
            : NetworkMenuImage(imageUrl: url, fit: BoxFit.cover),
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({
    required this.restaurantName,
    required this.description,
    required this.titleSize,
    required this.maxDescriptionLines,
  });

  final String restaurantName;
  final String description;
  final double titleSize;
  final int maxDescriptionLines;

  @override
  Widget build(BuildContext context) {
    final localeCode = context.watch<LocaleProvider>().localeCode;
    final isArabic = localeCode.startsWith('ar');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          restaurantName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          description.isEmpty
              ? (isArabic
                    ? 'طعام طازج وتوصيل سريع'
                    : 'Fresh food and fast delivery')
              : description,
          maxLines: maxDescriptionLines,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.deliveryFee,
    required this.isArabic,
    this.rating,
    this.reviewCount = 0,
  });

  final double deliveryFee;
  final bool isArabic;
  final double? rating;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    final hasReviews = rating != null && reviewCount > 0;
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        _MetaChip(
          icon: Icons.star_rounded,
          label: hasReviews
              ? '${rating!.toStringAsFixed(1)} ($reviewCount)'
              : (isArabic ? 'جديد على AlMenuPro' : 'New on AlMenuPro'),
        ),
        _MetaChip(
          icon: Icons.timer_outlined,
          label: isArabic ? '25-35 د' : '25-35 min',
        ),
        _MetaChip(
          icon: Icons.delivery_dining_outlined,
          label: deliveryFee <= 0
              ? (isArabic ? 'توصيل مجاني' : 'Free delivery')
              : '${deliveryFee.toStringAsFixed(3)} ${isArabic ? 'د.ك' : 'KWD'}',
        ),
      ],
    );
  }
}

class _PromoBanner extends StatelessWidget {
  const _PromoBanner({required this.session, required this.compact});

  final CustomerSessionProvider session;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();
    final isArabic = locale.isArabic;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.card_giftcard, color: AppTheme.brandOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.identified && session.isReturning
                      ? (isArabic
                            ? 'مرحباً بعودتك، ${session.welcomeName}'
                            : 'Welcome back, ${session.welcomeName}')
                      : (isArabic ? 'عرض الكاش باك' : 'Cashback offer'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.brandMaroon,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  session.identified && session.walletBalance > 0
                      ? (isArabic
                            ? 'رصيد محفظتك ${session.walletBalance.toStringAsFixed(3)} د.ك — ${session.cashbackOfferLabel}'
                            : 'Wallet balance ${session.walletBalance.toStringAsFixed(3)} KWD — ${session.cashbackOfferLabel}')
                      : session.cashbackOfferLabel,
                  maxLines: compact ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9A3412),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.brandOrange),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class StorefrontItemCard extends StatelessWidget {
  const StorefrontItemCard({
    super.key,
    required this.item,
    required this.onAdd,
    this.dense = false,
  });

  final MenuItem item;
  final VoidCallback onAdd;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final localeCode = context.watch<LocaleProvider>().localeCode;
    final name = item.localizedName(localeCode);
    final description = item.localizedDescription(localeCode);
    final currency = localeCode.startsWith('ar') ? 'د.ك' : 'KWD';
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = dense || constraints.maxWidth < 200;
        final showDescription = !compact && description.trim().isNotEmpty;
        final radius = BorderRadius.circular(14);

        return Material(
          color: Colors.white,
          elevation: 1,
          shadowColor: Colors.black12,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    item.imageUrl.trim().isEmpty
                        ? const ColoredBox(
                            color: Color(0xFFFFF4E5),
                            child: Icon(Icons.cookie_outlined, size: 36),
                          )
                        : NetworkMenuImage(
                            imageUrl: item.imageUrl,
                            fit: BoxFit.cover,
                          ),
                    if (item.hasDiscount && item.discountPercent != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: ProductDiscountBadge(
                          percent: item.discountPercent!,
                          compact: compact,
                        ),
                      ),
                    if ((item.catalogBadge ?? '').trim().isNotEmpty)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: MenuEngineeringBadge.forItem(
                          item,
                          compact: compact,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 8 : 10,
                  compact ? 6 : 8,
                  compact ? 8 : 10,
                  compact ? 6 : 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        fontSize: compact ? 12 : 13.5,
                      ),
                    ),
                    if (showDescription) ...[
                      const SizedBox(height: 3),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                          height: 1.25,
                        ),
                      ),
                    ],
                    if (item.hasDiscount) ...[
                      const SizedBox(height: 6),
                      ProductSalePrice(item: item, compact: compact),
                    ],
                  ],
                ),
              ),
              Material(
                color: AppTheme.brandOrange,
                child: InkWell(
                  onTap: onAdd,
                  child: SizedBox(
                    height: compact ? 38 : 42,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 10 : 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.shopping_cart,
                            color: Colors.white,
                            size: compact ? 16 : 18,
                          ),
                          Expanded(
                            child: Text(
                              '${item.finalPrice.toStringAsFixed(3)} $currency',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: compact ? 12.5 : 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
