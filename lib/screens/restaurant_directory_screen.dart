import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/marketplace_restaurant.dart';
import '../providers/locale_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/auth_login_routes.dart';
import '../utils/restaurant_route.dart';
import '../utils/web_initial_route.dart';
import '../widgets/language_toggle_button.dart';
import '../widgets/network_menu_image.dart';

class RestaurantDirectoryScreen extends StatefulWidget {
  const RestaurantDirectoryScreen({super.key});

  @override
  State<RestaurantDirectoryScreen> createState() =>
      _RestaurantDirectoryScreenState();
}

class _RestaurantDirectoryScreenState extends State<RestaurantDirectoryScreen> {
  var _loading = true;
  String? _error;
  MarketplaceCatalog _catalog = const MarketplaceCatalog();
  final _searchController = TextEditingController();
  String _query = '';
  String _selectedCategory = 'all';
  String? _selectedArea;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await ApiService.instance.fetchMarketplaceCatalog();
      if (!mounted) return;
      if (catalog.restaurants.length == 1) {
        final path = kIsWeb ? currentWebPath() : '/';
        if (!AuthLoginRoutes.isStaffPath(path)) {
          Navigator.of(context).pushReplacementNamed(
            RestaurantRoute.menuPathForSlug(catalog.restaurants.first.slug),
          );
          return;
        }
      }
      setState(() {
        _catalog = catalog;
        _selectedArea ??=
            catalog.areas.isNotEmpty ? catalog.areas.first : 'القرين، قطعة 1';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  List<MarketplaceRestaurant> get _filtered {
    final q = _query.trim().toLowerCase();
    return _catalog.restaurants.where((restaurant) {
      if (_selectedCategory != 'all' &&
          !restaurant.categoryIds.contains(_selectedCategory)) {
        return false;
      }
      if (q.isEmpty) return true;
      final haystack = [
        restaurant.name,
        restaurant.description,
        restaurant.cuisineLine,
        restaurant.slug,
        ...restaurant.cuisines.map((tag) => '${tag.labelAr} ${tag.labelEn}'),
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  void _open(MarketplaceRestaurant restaurant) {
    Navigator.of(context).pushNamed(
      RestaurantRoute.menuPathForSlug(restaurant.slug),
    );
  }

  Future<void> _pickArea() async {
    final areas = _catalog.areas.isNotEmpty
        ? _catalog.areas
        : const ['القرين، قطعة 1', 'حولي', 'السالمية'];
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  AppStrings.of(context).tr('التوصيل إلى', 'Deliver to'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              ...areas.map(
                (area) => ListTile(
                  leading: Icon(
                    area == _selectedArea
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: AppTheme.brandOrange,
                  ),
                  title: Text(area),
                  onTap: () => Navigator.pop(context, area),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (selected != null && mounted) {
      setState(() => _selectedArea = selected);
    }
  }

  IconData _categoryIcon(String icon) {
    return switch (icon) {
      'apps' => Icons.apps_rounded,
      'lunch_dining' => Icons.lunch_dining_rounded,
      'ramen_dining' => Icons.ramen_dining_rounded,
      'cake' => Icons.cake_rounded,
      'local_cafe' => Icons.local_cafe_rounded,
      'outdoor_grill' => Icons.outdoor_grill_rounded,
      _ => Icons.restaurant_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final isArabic = strings.isArabic;
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;
    final filtered = _filtered;

    return Directionality(
      textDirection: context.watch<LocaleProvider>().textDirection,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.brandOrange),
                )
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(_error!, textAlign: TextAlign.center),
                          ),
                          FilledButton(
                            onPressed: _load,
                            child: Text(
                              strings.tr('إعادة المحاولة', 'Try again'),
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: AppTheme.brandOrange,
                      onRefresh: _load,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(child: _buildHeader(isArabic)),
                          SliverToBoxAdapter(child: _buildSearch(isArabic)),
                          SliverToBoxAdapter(
                            child: _buildCategoryChips(isArabic),
                          ),
                          if (filtered.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                child: Text(
                                  strings.tr(
                                    'لا توجد مطاعم مطابقة',
                                    'No matching restaurants',
                                  ),
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                isWide ? 24 : 12,
                                8,
                                isWide ? 24 : 12,
                                28,
                              ),
                              sliver: SliverGrid(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: isWide
                                      ? 3
                                      : width >= 600
                                          ? 2
                                          : 1,
                                  mainAxisSpacing: 14,
                                  crossAxisSpacing: 14,
                                  childAspectRatio: isWide
                                      ? 0.88
                                      : width >= 600
                                          ? 0.82
                                          : 0.98,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final restaurant = filtered[index];
                                    return _RestaurantMarketplaceCard(
                                      restaurant: restaurant,
                                      isArabic: isArabic,
                                      onTap: () => _open(restaurant),
                                    );
                                  },
                                  childCount: filtered.length,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isArabic) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: _pickArea,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      color: AppTheme.brandOrange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isArabic ? 'التوصيل إلى' : 'Deliver to',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _selectedArea ??
                                (isArabic ? 'اختر المنطقة' : 'Choose area'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.brandBlack,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF6B7280),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const LanguageToggleButton(compact: true),
        ],
      ),
    );
  }

  Widget _buildSearch(bool isArabic) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _query = value),
        decoration: InputDecoration(
          hintText: isArabic
              ? 'ابحث عن مطعم أو أكلة...'
              : 'Search restaurants or food...',
          prefixIcon: const Icon(Icons.search_rounded),
          filled: true,
          fillColor: const Color(0xFFF3F4F6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChips(bool isArabic) {
    final categories = _catalog.categories.isNotEmpty
        ? _catalog.categories
        : const [
            MarketplaceCategory(
              id: 'all',
              labelAr: 'الكل',
              labelEn: 'All',
              icon: 'apps',
            ),
          ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 86,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: categories.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final category = categories[index];
            final selected = category.id == _selectedCategory;
            return InkWell(
              onTap: () => setState(() => _selectedCategory = category.id),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 78,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.brandOrange.withValues(alpha: 0.12)
                      : const Color(0xFFF8F8F8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected
                        ? AppTheme.brandOrange
                        : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _categoryIcon(category.icon),
                      color: selected
                          ? AppTheme.brandOrange
                          : const Color(0xFF4B5563),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      category.label(isArabic),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? AppTheme.brandOrange
                            : const Color(0xFF374151),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RestaurantMarketplaceCard extends StatelessWidget {
  const _RestaurantMarketplaceCard({
    required this.restaurant,
    required this.isArabic,
    required this.onTap,
  });

  final MarketplaceRestaurant restaurant;
  final bool isArabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cover = restaurant.coverUrl.isNotEmpty
        ? restaurant.coverUrl
        : restaurant.logoUrl;
    final logo = restaurant.logoUrl.isNotEmpty
        ? restaurant.logoUrl
        : restaurant.coverUrl;

    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover.isNotEmpty)
                    NetworkMenuImage(imageUrl: cover, fit: BoxFit.cover)
                  else
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppTheme.brandMaroon, AppTheme.brandOrange],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        restaurant.name.trim().isNotEmpty
                            ? restaurant.name.trim()[0]
                            : 'م',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  Positioned(
                    top: 10,
                    left: isArabic ? null : 10,
                    right: isArabic ? 10 : null,
                    child: _StatusBadge(isOpen: restaurant.isOpen, isArabic: isArabic),
                  ),
                  if ((restaurant.promoLabel ?? '').trim().isNotEmpty)
                    Positioned(
                      top: 10,
                      left: isArabic ? 10 : null,
                      right: isArabic ? null : 10,
                      child: _PromoBadge(label: restaurant.promoLabel!.trim()),
                    ),
                  Positioned(
                    bottom: 10,
                    left: isArabic ? null : 12,
                    right: isArabic ? 12 : null,
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: logo.isNotEmpty
                          ? NetworkMenuImage(imageUrl: logo, fit: BoxFit.cover)
                          : ColoredBox(
                              color: const Color(0xFFFFF7ED),
                              child: Center(
                                child: Text(
                                  restaurant.name.trim().isNotEmpty
                                      ? restaurant.name.trim()[0]
                                      : 'م',
                                  style: const TextStyle(
                                    color: AppTheme.brandMaroon,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppTheme.brandBlack,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      restaurant.cuisineLine.isNotEmpty
                          ? restaurant.cuisineLine
                          : (isArabic ? 'متنوع' : 'Various'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (restaurant.rating > 0)
                          _MetaChip(
                            icon: Icons.star_rounded,
                            iconColor: const Color(0xFFF59E0B),
                            label: restaurant.reviewCount > 0
                                ? '${restaurant.rating.toStringAsFixed(1)} (${restaurant.reviewCount})'
                                : restaurant.rating.toStringAsFixed(1),
                          )
                        else
                          _MetaChip(
                            icon: Icons.auto_awesome,
                            iconColor: AppTheme.brandOrange,
                            label: isArabic ? 'جديد' : 'New',
                          ),
                        _MetaChip(
                          icon: Icons.schedule_rounded,
                          iconColor: const Color(0xFF64748B),
                          label: restaurant.deliveryTimeLabel,
                        ),
                        _MetaChip(
                          icon: Icons.delivery_dining_rounded,
                          iconColor: restaurant.freeDelivery ||
                                  (restaurant.deliveryFee ?? 1) <= 0
                              ? const Color(0xFF059669)
                              : const Color(0xFF64748B),
                          label: restaurant.deliveryFeeLabel(isArabic: isArabic),
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isOpen, required this.isArabic});

  final bool isOpen;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final color = isOpen ? const Color(0xFF059669) : const Color(0xFFDC2626);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isOpen
            ? (isArabic ? 'مفتوح' : 'Open')
            : (isArabic ? 'مغلق' : 'Closed'),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _PromoBadge extends StatelessWidget {
  const _PromoBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.brandOrange,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: iconColor),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF374151),
          ),
        ),
      ],
    );
  }
}
