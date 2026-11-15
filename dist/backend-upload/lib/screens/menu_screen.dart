import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/customer_restaurant_context.dart';
import '../models/delivery_zone.dart';
import '../models/menu_item.dart';
import '../models/offer.dart';
import '../models/restaurant.dart';
import '../models/restaurant_review.dart';
import '../models/restaurant_settings.dart';
import '../providers/cart_provider.dart';
import '../providers/customer_session_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/order_type_provider.dart';
import '../models/order.dart';
import '../services/api_service.dart';
import '../services/pending_review_service.dart';
import '../theme/app_theme.dart';
import '../utils/discount.dart';
import '../utils/dynamic_menu_sort.dart';
import '../utils/restaurant_route.dart';
import '../widgets/menu/customer_phone_gate.dart';
import '../widgets/menu/customization_dialog.dart';
import '../widgets/menu/free_delivery_progress_bar.dart';
import '../widgets/menu/menu_checkout_sheet.dart';
import '../widgets/menu/order_review_sheet.dart';
import '../widgets/menu/storefront_header.dart';
import '../widgets/menu/storefront_offers_banner.dart';
import '../l10n/app_strings.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({
    super.key,
    this.slug,
    this.dineInTableId,
    this.dineInTableName,
  });

  final String? slug;
  final String? dineInTableId;
  final String? dineInTableName;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  static const _pageSize = 24;
  static const _smartCategory = 'اختيارات على ذوقك';
  static const _offersCategory = 'العروض والخصومات';
  List<MenuItem> _items = [];
  List<Offer> _offers = const [];
  Restaurant? _restaurant;
  RestaurantSettings? _settings;
  List<DeliveryZone> _zones = const [];
  ReviewSummary _reviewSummary = const ReviewSummary();
  var _loading = true;
  var _loadingMore = false;
  var _retrying = false;
  var _total = 0;
  String? _error;
  String _selectedCategory = 'الكل';
  var _searchOpen = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _reviewPollTimer;
  var _reviewPromptOpen = false;
  final Set<String> _promptedOrderIds = {};

  @override
  void initState() {
    super.initState();
    _loadItems(autoRetry: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomerSessionProvider>().restore();
      final tableId = widget.dineInTableId?.trim();
      if (tableId != null && tableId.isNotEmpty) {
        context.read<CustomerSessionProvider>().bindDineInTable(
          tableId: tableId,
          tableName: widget.dineInTableName ?? '',
        );
        context.read<OrderTypeProvider>().setOrderType(OrderType.dineIn);
      }
      unawaited(_checkPendingReviews(forceUrlRate: true));
    });
    _reviewPollTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(_checkPendingReviews()),
    );
  }

  @override
  void dispose() {
    _reviewPollTimer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String get _restaurantId => _restaurant?.id ?? ApiService.defaultRestaurantId;

  String? get _menuSlug {
    final fromWidget = widget.slug?.trim().toLowerCase();
    if (fromWidget != null && fromWidget.isNotEmpty) return fromWidget;
    return RestaurantRoute.slugFromBrowserLocation();
  }

  CustomerRestaurantContext? get _restaurantContext {
    final restaurant = _restaurant;
    final settings = _settings;
    if (restaurant == null || settings == null) return null;
    return CustomerRestaurantContext(
      restaurant: restaurant,
      settings: settings,
    );
  }

  Future<void> _checkPendingReviews({bool forceUrlRate = false}) async {
    if (!mounted || _reviewPromptOpen) return;
    final slug = _menuSlug;
    final restaurantId = _restaurant?.id;
    if (slug == null || slug.isEmpty || restaurantId == null) return;

    final strings = AppStrings.read(context);
    final candidates = <PendingReviewRequest>[];

    if (forceUrlRate && kIsWeb) {
      final rateId =
          (Uri.base.queryParameters['rate'] ??
                  Uri.base.queryParameters['review'] ??
                  '')
              .trim();
      if (rateId.isNotEmpty) {
        candidates.add(
          PendingReviewRequest(
            orderId: rateId,
            restaurantId: restaurantId,
            restaurantSlug: slug,
            restaurantName: _restaurant?.name ?? '',
          ),
        );
      }
    }

    candidates.addAll(await PendingReviewService.instance.list());

    for (final pending in candidates) {
      if (_promptedOrderIds.contains(pending.orderId)) continue;
      if (await PendingReviewService.instance.wasDismissed(pending.orderId)) {
        continue;
      }

      final eligibility = await ApiService.instance.fetchReviewEligibility(
        orderId: pending.orderId,
        slug: slug,
        restaurantId: restaurantId,
      );

      if (!eligibility.eligible) {
        if (eligibility.reason == 'already_reviewed') {
          await PendingReviewService.instance.remove(pending.orderId);
        }
        continue;
      }

      if (!mounted || _reviewPromptOpen) return;
      _reviewPromptOpen = true;
      _promptedOrderIds.add(pending.orderId);
      final submitted = await OrderReviewSheet.show(
        context,
        orderId: pending.orderId,
        restaurantId: restaurantId,
        restaurantSlug: slug,
        restaurantName: _restaurant?.name ?? '',
        invoiceNumber: eligibility.invoiceNumber,
        customerName: eligibility.customerName,
        strings: strings,
      );
      _reviewPromptOpen = false;

      if (submitted == true) {
        await PendingReviewService.instance.remove(pending.orderId);
        final summary = await ApiService.instance.fetchReviewSummary(
          slug: slug,
        );
        if (mounted) setState(() => _reviewSummary = summary);
      } else {
        await PendingReviewService.instance.markDismissed(pending.orderId);
      }
      break;
    }
  }

  Future<Restaurant> _resolveRestaurant() async {
    final slug = (widget.slug?.trim().toLowerCase().isNotEmpty == true)
        ? widget.slug!.trim().toLowerCase()
        : RestaurantRoute.slugFromBrowserLocation();
    if (slug != null && slug.isNotEmpty) {
      return ApiService.instance.fetchPublicRestaurant(slug: slug);
    }
    throw Exception(
      AppStrings.read(context).tr('المطعم غير موجود', 'Restaurant not found'),
    );
  }

  Future<void> _loadItems({bool autoRetry = false, bool reset = true}) async {
    if (reset) {
      setState(() {
        _loading = _items.isEmpty;
        _retrying = _items.isNotEmpty;
        _error = null;
      });
    } else {
      if (_loadingMore || _items.length >= _total) return;
      setState(() => _loadingMore = true);
    }

    try {
      if (reset || _restaurant == null) {
        _restaurant = await _resolveRestaurant();
        if (mounted) {
          context.read<CartProvider>().bindRestaurant(_restaurantId);
        }
      }
      final page = await ApiService.instance.fetchItemsPage(
        restaurantId: _restaurantId,
        lite: true,
        limit: _pageSize,
        offset: reset ? 0 : _items.length,
        channel: 'website',
      );
      if (reset) {
        try {
          final settings = await ApiService.instance.fetchSettings(
            restaurantId: _restaurantId,
          );
          final zones = await ApiService.instance.fetchDeliveryZones(
            restaurantId: _restaurantId,
          );
          if (mounted) {
            _settings = settings;
            _zones = zones;
          }
        } catch (_) {}
        try {
          final offers = await ApiService.instance.fetchOffers(
            restaurantId: _restaurantId,
          );
          if (mounted) _offers = offers;
        } catch (_) {
          if (mounted) _offers = const [];
        }
        try {
          final summary = await ApiService.instance.fetchReviewSummary(
            slug: _menuSlug,
            restaurantId: _restaurantId,
          );
          if (mounted) _reviewSummary = summary;
        } catch (_) {}
        unawaited(_checkPendingReviews());
      }
      if (!mounted) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        _total = page.total;
        _loading = false;
        _loadingMore = false;
        _retrying = false;
        _error = null;
      });
    } catch (error) {
      if (autoRetry && _items.isEmpty) {
        try {
          _restaurant = await _resolveRestaurant();
          final page = await ApiService.instance.fetchItemsPage(
            restaurantId: _restaurantId,
            lite: true,
            limit: _pageSize,
            offset: 0,
            channel: 'website',
          );
          if (!mounted) return;
          context.read<CartProvider>().bindRestaurant(_restaurantId);
          setState(() {
            _items = page.items;
            _total = page.total;
            _loading = false;
            _retrying = false;
            _error = null;
          });
          return;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _retrying = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _addToCart(MenuItem item) {
    if (item.hasCustomizations) {
      showCustomizationDialog(context, item);
      return;
    }
    final strings = AppStrings.read(context);
    final displayName = item.localizedName(strings.localeCode);
    context.read<CartProvider>().addMenuItem(
      item,
      offerId: matchingOfferIdForItem(item, _offers),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(strings.addedToCart(displayName)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<String> _categories(List<MenuItem> items) {
    final categories = <String>[
      'الكل',
      if (_settings?.smartUpsellEnabled != false) _smartCategory,
      if (_offers.isNotEmpty || items.any((item) => item.hasDiscount))
        _offersCategory,
    ];
    final seen = categories.toSet();
    for (final item in items) {
      final name = item.categoryName.trim();
      if (name.isNotEmpty && seen.add(name)) {
        categories.add(name);
      }
    }
    return categories;
  }

  List<MenuItem> _filteredItems(List<MenuItem> items) {
    List<MenuItem> result;
    if (_selectedCategory == _offersCategory) {
      result = itemsForOffersTab(items, _offers, originalItems: _items);
    } else if (_selectedCategory == _smartCategory) {
      if (_settings?.smartUpsellEnabled == false) {
        result = items;
      } else {
        final bumpIds = _settings?.impulseBumpItemIds ?? const <int>[];
        if (bumpIds.isNotEmpty) {
          final byId = {for (final item in items) item.id: item};
          final picked = bumpIds
              .map((id) => byId[id])
              .whereType<MenuItem>()
              .toList();
          result = picked.isNotEmpty ? picked : items;
        } else {
          final maxPrice = _settings?.impulseBumpMaxPrice ?? 2;
          final cheap = items.where((item) => item.price <= maxPrice).toList()
            ..sort((a, b) => a.price.compareTo(b.price));
          if (cheap.isNotEmpty) {
            result = cheap.take(8).toList();
          } else {
            final sorted = [...items]
              ..sort((a, b) => a.price.compareTo(b.price));
            result = sorted.take(8).toList();
          }
        }
      }
    } else if (_selectedCategory == 'الكل') {
      result = items;
    } else {
      result = items
          .where((item) => item.categoryName.trim() == _selectedCategory)
          .toList();
    }
    return sortCatalogItems(_applySearch(result), settings: _settings);
  }

  List<MenuItem> _applySearch(List<MenuItem> items) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return items;
    return items.where((item) {
      final haystack = [
        item.name,
        item.nameAr,
        item.nameEn,
        item.description,
        item.descriptionAr,
        item.descriptionEn,
        item.categoryName,
        item.categoryNameEn,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchQuery = '';
        _searchController.clear();
      }
    });
    if (_searchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchFocus.requestFocus();
      });
    }
  }

  Future<void> _shareMenu() async {
    final slug = (_restaurant?.slug ?? widget.slug ?? '').trim();
    final uri = Uri.base;
    final origin =
        '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
    final link = slug.isEmpty ? uri.toString() : '$origin/$slug';
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    final arabic = context.read<LocaleProvider>().isArabic;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(arabic ? 'تم نسخ رابط المنيو' : 'Menu link copied'),
      ),
    );
  }

  int _gridColumns(double width) {
    if (width >= 1400) return 5;
    if (width >= 1100) return 4;
    if (width >= 800) return 3;
    return 2;
  }

  double _gridChildAspect(int columns) {
    switch (columns) {
      case 5:
        return 0.80;
      case 4:
        return 0.76;
      case 3:
        return 0.72;
      default:
        return 0.60;
    }
  }

  SliverToBoxAdapter _offersSectionHeader(String title, double pad) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad, 10, pad, 6),
        child: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: AppTheme.brandMaroon,
          ),
        ),
      ),
    );
  }

  SliverPadding _offersItemGrid(
    List<MenuItem> items, {
    required int columns,
    required double pad,
    required double gap,
  }) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(pad, 4, pad, 16),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: gap,
          mainAxisSpacing: gap,
          childAspectRatio: _gridChildAspect(columns),
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          return StorefrontItemCard(
            item: items[index],
            onAdd: () => _addToCart(items[index]),
            dense: columns <= 2,
          );
        }, childCount: items.length),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final session = context.watch<CustomerSessionProvider>();

    return Directionality(
      textDirection: context.watch<LocaleProvider>().textDirection,
      child: Scaffold(
        backgroundColor: AppTheme.brandBackground,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              _buildBody(cartReserve: cart.items.isEmpty ? 0 : 132),
              if (cart.items.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _StorefrontCartBar(
                    itemCount: cart.itemCount,
                    totalPrice: cart.totalPrice,
                    settings: _settings,
                    onCheckout: _openCartAndSmartSalesman,
                  ),
                ),
              if (!session.identified) const CustomerPhoneGate(),
            ],
          ),
        ),
      ),
    );
  }

  void _openCartAndSmartSalesman() {
    MenuCheckoutSheet.show(
      context,
      restaurantContext: _restaurantContext,
      initialStep: 1,
    );
  }

  Widget _buildBody({double cartReserve = 0}) {
    final strings = AppStrings.of(context);
    if (_loading && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppTheme.brandOrange),
            const SizedBox(height: 16),
            Text(
              strings.tr('جاري تحميل المنيو...', 'Loading menu...'),
              style: const TextStyle(color: AppTheme.brandBlack),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return _ErrorState(
        message: _error ?? strings.noItemsAvailable,
        onRetry: () => _loadItems(autoRetry: true),
      );
    }

    final pricedItems = applyOfferDiscountsToItems(_items, _offers);
    final categories = _categories(pricedItems);
    final filtered = _filteredItems(pricedItems);
    final offerGroups =
        _selectedCategory == _offersCategory && _searchQuery.trim().isEmpty
        ? groupItemsForOffersTab(pricedItems, _offers, originalItems: _items)
        : null;

    return Column(
      children: [
        if (_error != null || _retrying)
          Material(
            color: const Color(0xFFFFF4E5),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _retrying
                        ? strings.tr('جاري تحديث المنيو...', 'Updating menu...')
                        : strings.tr(
                            'تعذر التحديث. يمكنك متابعة التصفح.',
                            'Update failed. You can continue browsing.',
                          ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  TextButton(
                    onPressed: _retrying ? null : () => _loadItems(),
                    child: Text(strings.tr('إعادة المحاولة', 'Try again')),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.pixels >=
                      notification.metrics.maxScrollExtent - 480 &&
                  !_loadingMore &&
                  _items.length < _total) {
                _loadItems(reset: false);
              }
              return false;
            },
            child: RefreshIndicator(
              color: AppTheme.brandOrange,
              onRefresh: () => _loadItems(),
              child: LayoutBuilder(
                builder: (context, viewport) {
                  final maxWidth = viewport.maxWidth >= 1280
                      ? 1240.0
                      : viewport.maxWidth;
                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(
                            child: StorefrontHero(
                              restaurantName: _restaurant?.name ?? 'AlMenuPro',
                              description:
                                  _settings?.restaurantDescription ?? '',
                              logoUrl: _settings?.logoUrl ?? '',
                              heroImageUrl: _settings?.heroImageUrl ?? '',
                              deliveryFee: _zones.isEmpty
                                  ? 0
                                  : _zones.first.deliveryFee,
                              session: context.watch<CustomerSessionProvider>(),
                              isArabic: context
                                  .watch<LocaleProvider>()
                                  .isArabic,
                              rating: _reviewSummary.hasReviews
                                  ? _reviewSummary.average
                                  : null,
                              reviewCount: _reviewSummary.count,
                              onSearch: _toggleSearch,
                              onShare: _shareMenu,
                              onToggleLanguage: () =>
                                  context.read<LocaleProvider>().toggle(),
                            ),
                          ),
                          if (_searchOpen)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  8,
                                  10,
                                  0,
                                ),
                                child: TextField(
                                  controller: _searchController,
                                  focusNode: _searchFocus,
                                  onChanged: (value) =>
                                      setState(() => _searchQuery = value),
                                  decoration: InputDecoration(
                                    hintText:
                                        context.watch<LocaleProvider>().isArabic
                                        ? 'ابحث في المنيو...'
                                        : 'Search the menu...',
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon: _searchQuery.isEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.close),
                                            onPressed: _toggleSearch,
                                          )
                                        : IconButton(
                                            icon: const Icon(Icons.clear),
                                            onPressed: () {
                                              _searchController.clear();
                                              setState(() => _searchQuery = '');
                                            },
                                          ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFE0D6CC),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFE0D6CC),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (_offers.isNotEmpty)
                            SliverToBoxAdapter(
                              child: StorefrontOffersBanner(
                                offers: _offers,
                                onOpenOffers: () {
                                  setState(
                                    () => _selectedCategory = _offersCategory,
                                  );
                                },
                              ),
                            ),
                          SliverToBoxAdapter(
                            child: _CategoryBar(
                              categories: categories,
                              selected: _selectedCategory,
                              labelFor: (category) {
                                if (category == _smartCategory) {
                                  return strings.tr(
                                    'اختيارات على ذوقك',
                                    'Picks for you',
                                  );
                                }
                                if (category == _offersCategory) {
                                  return strings.tr(
                                    'العروض والخصومات',
                                    'Offers & discounts',
                                  );
                                }
                                if (category == 'الكل') return strings.all;
                                final matching = pricedItems.where(
                                  (item) =>
                                      item.categoryName.trim() == category,
                                );
                                return matching.isEmpty
                                    ? category
                                    : matching.first.localizedCategoryName(
                                        strings.localeCode,
                                      );
                              },
                              onSelected: (value) {
                                setState(() => _selectedCategory = value);
                              },
                            ),
                          ),
                          if (filtered.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                child: Text(
                                  _searchQuery.trim().isNotEmpty
                                      ? (context
                                                .watch<LocaleProvider>()
                                                .isArabic
                                            ? 'لا توجد نتائج للبحث'
                                            : 'No search results')
                                      : _selectedCategory == _offersCategory
                                      ? strings.tr(
                                          'لا توجد أصناف مخفضة حالياً',
                                          'No discounted items right now',
                                        )
                                      : strings.noItemsInCategory,
                                  style: const TextStyle(
                                    color: AppTheme.brandBlack,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            )
                          else
                            SliverLayoutBuilder(
                              builder: (context, constraints) {
                                final width = constraints.crossAxisExtent;
                                final columns = _gridColumns(width);
                                final pad = width >= 900
                                    ? 20.0
                                    : width >= 600
                                    ? 12.0
                                    : 10.0;
                                final gap = width >= 900 ? 14.0 : 8.0;
                                final groups = offerGroups;
                                if (groups != null) {
                                  return SliverMainAxisGroup(
                                    slivers: [
                                      if (groups.featured.isNotEmpty) ...[
                                        _offersSectionHeader(
                                          strings.tr(
                                            'عروض مميزة',
                                            'Featured offers',
                                          ),
                                          pad,
                                        ),
                                        _offersItemGrid(
                                          groups.featured,
                                          columns: columns,
                                          pad: pad,
                                          gap: gap,
                                        ),
                                      ],
                                      if (groups.rest.isNotEmpty) ...[
                                        if (groups.featured.isNotEmpty)
                                          _offersSectionHeader(
                                            strings.tr(
                                              'باقي المنيو',
                                              'More from the menu',
                                            ),
                                            pad,
                                          ),
                                        _offersItemGrid(
                                          groups.rest,
                                          columns: columns,
                                          pad: pad,
                                          gap: gap,
                                        ),
                                      ],
                                    ],
                                  );
                                }

                                return _offersItemGrid(
                                  filtered,
                                  columns: columns,
                                  pad: pad,
                                  gap: gap,
                                );
                              },
                            ),
                          if (_items.length < _total || _loadingMore)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  0,
                                  10,
                                  16,
                                ),
                                child: Center(
                                  child: _loadingMore
                                      ? const CircularProgressIndicator(
                                          color: AppTheme.brandOrange,
                                        )
                                      : TextButton(
                                          onPressed: () =>
                                              _loadItems(reset: false),
                                          child: Text(
                                            '${strings.tr('عرض المزيد', 'Show more')} (${_items.length}/$_total)',
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          if (cartReserve > 0)
                            SliverToBoxAdapter(
                              child: SizedBox(
                                height:
                                    cartReserve +
                                    MediaQuery.paddingOf(context).bottom,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StorefrontCartBar extends StatelessWidget {
  const _StorefrontCartBar({
    required this.itemCount,
    required this.totalPrice,
    required this.onCheckout,
    this.settings,
  });

  final int itemCount;
  final double totalPrice;
  final VoidCallback onCheckout;
  final RestaurantSettings? settings;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final showFreeDelivery = settings != null && settings!.hasFreeDeliveryGoal;

    return Material(
      color: Colors.white,
      elevation: 16,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showFreeDelivery) ...[
                    FreeDeliveryProgressBar(
                      compact: true,
                      subtotal: totalPrice,
                      threshold: settings!.freeDeliveryThreshold,
                      baseDeliveryFee: 1,
                      strings: strings,
                    ),
                    const SizedBox(height: 8),
                  ],
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 360;
                      return FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.brandMaroon,
                          minimumSize: const Size.fromHeight(48),
                          padding: EdgeInsets.symmetric(
                            vertical: narrow ? 10 : 12,
                            horizontal: narrow ? 10 : 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        onPressed: onCheckout,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.brandOrange,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$itemCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                strings.continueOrder,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: narrow ? 14 : 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: AlignmentDirectional.centerEnd,
                                child: Text(
                                  '${totalPrice.toStringAsFixed(3)} ${strings.currency}',
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: narrow ? 13 : 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.categories,
    required this.selected,
    required this.onSelected,
    required this.labelFor,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;
  final String Function(String category) labelFor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSmart = category == 'اختيارات على ذوقك';
          final isOffers = category == 'العروض والخصومات';
          final isSelected = category == selected;

          return FilterChip(
            avatar: isSmart || isOffers
                ? Icon(
                    isOffers ? Icons.local_offer_outlined : Icons.auto_awesome,
                    size: 16,
                    color: isSelected ? Colors.white : AppTheme.brandMaroon,
                  )
                : null,
            label: Text(labelFor(category), overflow: TextOverflow.ellipsis),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            selected: isSelected,
            showCheckmark: false,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : AppTheme.brandBlack,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
            backgroundColor: isSmart || isOffers
                ? const Color(0xFFFFF4E5)
                : Colors.white,
            selectedColor: isSmart || isOffers
                ? AppTheme.brandMaroon
                : AppTheme.brandOrange,
            side: BorderSide(
              color: isSelected
                  ? AppTheme.brandOrange
                  : const Color(0xFFE0D6CC),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            onSelected: (_) => onSelected(category),
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 56, color: AppTheme.brandOrange),
            const SizedBox(height: 16),
            Text(
              message.replaceFirst('Exception: ', ''),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.brandBlack),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandOrange,
              ),
              icon: const Icon(Icons.refresh),
              label: Text(
                AppStrings.of(context).tr('إعادة المحاولة', 'Try again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
