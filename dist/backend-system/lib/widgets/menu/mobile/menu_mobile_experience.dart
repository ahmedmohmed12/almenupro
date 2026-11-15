import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_strings.dart';
import '../../../models/menu_item.dart';
import '../../../providers/locale_provider.dart';
import '../../../theme/app_theme.dart';
import '../../network_menu_image.dart';
import 'menu_grid_item_card.dart';

class MenuMobileExperience extends StatefulWidget {
  const MenuMobileExperience({
    super.key,
    required this.restaurantName,
    required this.heroImageUrl,
    required this.categoryTags,
    required this.categories,
    required this.items,
    required this.allItems,
    required this.localeCode,
    required this.strings,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.onAddToCart,
    required this.onRefresh,
  });

  final String restaurantName;
  final String heroImageUrl;
  final String categoryTags;
  final List<String> categories;
  final List<MenuItem> items;
  final List<MenuItem> allItems;
  final String localeCode;
  final AppStrings strings;
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;
  final ValueChanged<MenuItem> onAddToCart;
  final Future<void> Function() onRefresh;

  @override
  State<MenuMobileExperience> createState() => _MenuMobileExperienceState();
}

class _MenuMobileExperienceState extends State<MenuMobileExperience> {
  var _isFavorite = false;

  String _categoryLabel(String category) {
    if (category == widget.strings.all) return widget.strings.all;
    for (final item in widget.allItems) {
      if (item.categoryName.trim() == category) {
        return item.localizedCategoryName(widget.localeCode);
      }
    }
    return category;
  }

  bool _isHotCategory(String category) {
    return category.contains('🔥') || category.contains('ذوقك');
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;

    return RefreshIndicator(
      color: AppTheme.brandOrange,
      onRefresh: widget.onRefresh,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            stretch: true,
            backgroundColor: AppTheme.brandMaroon,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _HeroImage(imageUrl: widget.heroImageUrl),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.55),
                          Colors.black.withValues(alpha: 0.25),
                          Colors.black.withValues(alpha: 0.5),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: topPadding + 8,
                    left: 12,
                    right: 12,
                    child: _HeaderActions(
                      isFavorite: _isFavorite,
                      onBack: Navigator.of(context).canPop()
                          ? () => Navigator.of(context).maybePop()
                          : null,
                      onSearch: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              widget.strings.isArabic
                                  ? 'البحث قريباً'
                                  : 'Search coming soon',
                            ),
                          ),
                        );
                      },
                      onShare: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              widget.strings.isArabic
                                  ? 'مشاركة الرابط'
                                  : 'Share link',
                            ),
                          ),
                        );
                      },
                      onFavorite: () =>
                          setState(() => _isFavorite = !_isFavorite),
                      onLanguage: () =>
                          context.read<LocaleProvider>().toggle(),
                      localeCode: widget.localeCode,
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, 0.85),
                    child: _RestaurantLogo(name: widget.restaurantName),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -20),
              child: _RestaurantDetailsCard(
                name: widget.restaurantName,
                tags: widget.categoryTags,
                strings: widget.strings,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _ProBanner(strings: widget.strings),
          ),
          SliverToBoxAdapter(
            child: _OffersCarousel(strings: widget.strings),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _CategoryTabsDelegate(
              categories: widget.categories,
              selected: widget.selectedCategory,
              labelFor: _categoryLabel,
              isHot: _isHotCategory,
              onSelected: widget.onCategorySelected,
            ),
          ),
          if (widget.items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  widget.strings.noItemsInCategory,
                  style: GoogleFonts.cairo(color: AppTheme.brandBlack),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = widget.items[index];
                    return MenuGridItemCard(
                      item: item,
                      localeCode: widget.localeCode,
                      strings: widget.strings,
                      onAdd: () => widget.onAddToCart(item),
                    );
                  },
                  childCount: widget.items.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeroImage extends StatelessWidget {
  const _HeroImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isEmpty) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.brandMaroon, AppTheme.brandBlack],
          ),
        ),
      );
    }

    return NetworkMenuImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(color: AppTheme.brandMaroon),
    );
  }
}

class _HeaderActions extends StatelessWidget {
  const _HeaderActions({
    required this.isFavorite,
    required this.onSearch,
    required this.onShare,
    required this.onFavorite,
    required this.onLanguage,
    required this.localeCode,
    this.onBack,
  });

  final bool isFavorite;
  final VoidCallback? onBack;
  final VoidCallback onSearch;
  final VoidCallback onShare;
  final VoidCallback onFavorite;
  final VoidCallback onLanguage;
  final String localeCode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null) _CircleIcon(icon: Icons.arrow_back, onTap: onBack!),
        const Spacer(),
        _CircleIcon(icon: Icons.search, onTap: onSearch),
        const SizedBox(width: 8),
        _CircleIcon(icon: Icons.share_outlined, onTap: onShare),
        const SizedBox(width: 8),
        _CircleIcon(
          icon: isFavorite ? Icons.favorite : Icons.favorite_border,
          onTap: onFavorite,
          iconColor: isFavorite ? AppTheme.brandOrange : Colors.white,
        ),
        const SizedBox(width: 8),
        _CircleIcon(
          label: localeCode.startsWith('ar') ? 'EN' : 'ع',
          onTap: onLanguage,
        ),
      ],
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({
    this.icon,
    this.label,
    required this.onTap,
    this.iconColor = Colors.white,
  }) : assert(icon != null || label != null);

  final IconData? icon;
  final String? label;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
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
                    style: GoogleFonts.cairo(
                      color: AppTheme.brandOrange,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  )
                : Icon(icon, color: iconColor, size: 20),
          ),
        ),
      ),
    );
  }
}

class _RestaurantLogo extends StatelessWidget {
  const _RestaurantLogo({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0] : 'A';

    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: AppTheme.brandOrange, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: GoogleFonts.cairo(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: AppTheme.brandMaroon,
        ),
      ),
    );
  }
}

class _RestaurantDetailsCard extends StatelessWidget {
  const _RestaurantDetailsCard({
    required this.name,
    required this.tags,
    required this.strings,
  });

  final String name;
  final String tags;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: GoogleFonts.cairo(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.brandBlack,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tags,
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  color: const Color(0xFF666666),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.star_rounded,
                      color: AppTheme.brandOrange, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    '4.8',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    strings.isArabic ? ' (120+ تقييم)' : ' (120+ reviews)',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.delivery_dining_outlined,
                      size: 18, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    strings.isArabic ? '30-45 د' : '30-45 min',
                    style: GoogleFonts.cairo(fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.payments_outlined,
                      size: 18, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    strings.isArabic
                        ? 'رسوم توصيل حسب المنطقة'
                        : 'Delivery fee by area',
                    style: GoogleFonts.cairo(fontSize: 12),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.brandMaroon.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'AlMenuPro',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.brandMaroon,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProBanner extends StatelessWidget {
  const _ProBanner({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.brandMaroon,
              AppTheme.brandMaroon.withValues(alpha: 0.85),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.brandOrange.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.local_offer_outlined,
                  color: AppTheme.brandOrange, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                strings.isArabic
                    ? 'عروض حصرية على AlMenuPro — اطلب الآن'
                    : 'Exclusive AlMenuPro offers — order now',
                style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OffersCarousel extends StatelessWidget {
  const _OffersCarousel({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final offers = strings.isArabic
        ? ['خصم 10% على الطلب الأول', 'توصيل مجاني للطلبات +15 د.ك', 'وجبة مجانية']
        : ['10% off first order', 'Free delivery over 15 KWD', 'Free item promo'];

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: offers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          return Container(
            width: 200,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.brandOrange.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  index == 0
                      ? Icons.percent
                      : index == 1
                          ? Icons.local_shipping_outlined
                          : Icons.card_giftcard_outlined,
                  color: AppTheme.brandOrange,
                  size: 22,
                ),
                const SizedBox(height: 6),
                Text(
                  offers[index],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.brandBlack,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CategoryTabsDelegate extends SliverPersistentHeaderDelegate {
  _CategoryTabsDelegate({
    required this.categories,
    required this.selected,
    required this.labelFor,
    required this.isHot,
    required this.onSelected,
  });

  final List<String> categories;
  final String selected;
  final String Function(String) labelFor;
  final bool Function(String) isHot;
  final ValueChanged<String> onSelected;

  @override
  double get minExtent => 52;

  @override
  double get maxExtent => 52;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: AppTheme.brandBackground,
      elevation: overlapsContent ? 2 : 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppTheme.brandMaroon.withValues(alpha: 0.08)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final category = categories[index];
                  final isSelected = category == selected;
                  final label = labelFor(category);
                  final hot = isHot(category);

                  return GestureDetector(
                    onTap: () => onSelected(category),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: isSelected
                                ? AppTheme.brandOrange
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hot) ...[
                            const Icon(Icons.local_fire_department,
                                size: 16, color: AppTheme.brandOrange),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            label,
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              fontWeight:
                                  isSelected ? FontWeight.w800 : FontWeight.w500,
                              color: isSelected
                                  ? AppTheme.brandMaroon
                                  : const Color(0xFF666666),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.tune, color: AppTheme.brandMaroon),
              onPressed: () {},
              tooltip: 'Filter',
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CategoryTabsDelegate oldDelegate) {
    return oldDelegate.selected != selected ||
        oldDelegate.categories.length != categories.length;
  }
}
