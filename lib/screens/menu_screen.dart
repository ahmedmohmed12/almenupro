import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cart_item.dart';
import '../models/customer_restaurant_context.dart';
import '../models/delivery_zone.dart';
import '../models/menu_item.dart';
import '../models/offer.dart';
import '../models/restaurant.dart';
import '../models/restaurant_settings.dart';
import '../providers/cart_provider.dart';
import '../providers/customer_session_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/menu/customer_phone_gate.dart';
import '../widgets/menu/free_delivery_progress_bar.dart';
import '../widgets/menu/menu_checkout_sheet.dart';
import '../widgets/menu/storefront_header.dart';
import '../widgets/menu/storefront_offers_banner.dart';
import '../widgets/pos/smart_salesman_widget.dart';
import '../l10n/app_strings.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key, this.slug});

  final String? slug;

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
  var _loading = true;
  var _loadingMore = false;
  var _retrying = false;
  var _total = 0;
  String? _error;
  String _selectedCategory = 'اختيارات على ذوقك';

  @override
  void initState() {
    super.initState();
    _loadItems(autoRetry: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomerSessionProvider>().restore();
    });
  }

  String get _restaurantId =>
      _restaurant?.id ?? ApiService.defaultRestaurantId;

  CustomerRestaurantContext? get _restaurantContext {
    final restaurant = _restaurant;
    final settings = _settings;
    if (restaurant == null || settings == null) return null;
    return CustomerRestaurantContext(
      restaurant: restaurant,
      settings: settings,
    );
  }

  Future<Restaurant> _resolveRestaurant() async {
    final slug = widget.slug?.trim().toLowerCase();
    if (slug != null && slug.isNotEmpty) {
      return ApiService.instance.fetchPublicRestaurant(slug: slug);
    }
    final restaurants = await ApiService.instance.fetchPublicRestaurants();
    if (restaurants.isEmpty) {
      throw Exception('لا توجد مطاعم متاحة حالياً');
    }
    return restaurants.firstWhere(
      (entry) => entry.id == ApiService.defaultRestaurantId,
      orElse: () => restaurants.first,
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

  void _addOfferToCart(Offer offer) {
    context.read<CartProvider>().applyOfferToCart(offer, _items);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تمت إضافة "${offer.title}" إلى السلة'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _addToCart(MenuItem item) {
    context.read<CartProvider>().addMenuItem(item);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تمت إضافة "${item.name}" إلى السلة'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<String> _categories(List<MenuItem> items) {
    final categories = <String>{
      if (_offers.isNotEmpty) _offersCategory,
      if (_settings?.smartUpsellEnabled != false) _smartCategory,
      'الكل',
    };
    for (final item in items) {
      if (item.categoryName.trim().isNotEmpty) {
        categories.add(item.categoryName.trim());
      }
    }
    return categories.toList();
  }

  List<MenuItem> _filteredItems(List<MenuItem> items) {
    if (_selectedCategory == _offersCategory) return const [];
    if (_selectedCategory == _smartCategory) {
      if (_settings?.smartUpsellEnabled == false) {
        return items;
      }
      final bumpIds = _settings?.impulseBumpItemIds ?? const <int>[];
      if (bumpIds.isNotEmpty) {
        final byId = {for (final item in items) item.id: item};
        final picked = bumpIds
            .map((id) => byId[id])
            .whereType<MenuItem>()
            .toList();
        if (picked.isNotEmpty) return picked;
      }
      final maxPrice = _settings?.impulseBumpMaxPrice ?? 2;
      final cheap = items.where((item) => item.price <= maxPrice).toList()
        ..sort((a, b) => a.price.compareTo(b.price));
      if (cheap.isNotEmpty) return cheap.take(8).toList();
      final sorted = [...items]..sort((a, b) => a.price.compareTo(b.price));
      return sorted.take(8).toList();
    }
    if (_selectedCategory == 'الكل') return items;
    return items
        .where((item) => item.categoryName.trim() == _selectedCategory)
        .toList();
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
        return 0.86;
      case 4:
        return 0.82;
      case 3:
        return 0.78;
      default:
        return 0.72;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final session = context.watch<CustomerSessionProvider>();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.brandBackground,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              _buildBody(),
              if (!session.identified) const CustomerPhoneGate(),
            ],
          ),
        ),
        bottomNavigationBar: cart.isEmpty
            ? null
            : _FloatingCartBar(
                itemCount: cart.itemCount,
                totalPrice: cart.totalPrice,
                cartItems: cart.items,
                settings: _settings,
                restaurantId: _restaurantId,
                onAddSuggested: (item) =>
                    context.read<CartProvider>().addMenuItem(item),
                onCheckout: () => MenuCheckoutSheet.show(
                  context,
                  restaurantContext: _restaurantContext,
                ),
              ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.brandOrange),
            SizedBox(height: 16),
            Text(
              'جاري تحميل المنيو...',
              style: TextStyle(color: AppTheme.brandBlack),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return _ErrorState(
        message: _error ?? 'لا توجد أصناف متاحة حالياً',
        onRetry: () => _loadItems(autoRetry: true),
      );
    }

    final categories = _categories(_items);
    final filtered = _filteredItems(_items);

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
                        ? 'جاري تحديث المنيو...'
                        : 'تعذر التحديث. يمكنك متابعة التصفح.',
                    style: const TextStyle(fontSize: 13),
                  ),
                  TextButton(
                    onPressed: _retrying ? null : () => _loadItems(),
                    child: const Text('إعادة المحاولة'),
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
                final maxWidth = viewport.maxWidth >= 1280 ? 1240.0 : viewport.maxWidth;
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: StorefrontHero(
                    restaurantName: _restaurant?.name ?? 'AlMenuPro',
                    description: _settings?.restaurantDescription ?? '',
                    logoUrl: _settings?.logoUrl ?? '',
                    deliveryFee: _zones.isEmpty ? 0 : _zones.first.deliveryFee,
                    session: context.watch<CustomerSessionProvider>(),
                  ),
                ),
                if (_offers.isNotEmpty)
                  SliverToBoxAdapter(
                    child: StorefrontOffersBanner(
                      offers: _offers,
                      onAdd: _addOfferToCart,
                    ),
                  ),
                SliverToBoxAdapter(
                  child: _CategoryBar(
                    categories: categories,
                    selected: _selectedCategory,
                    onSelected: (value) {
                      setState(() => _selectedCategory = value);
                    },
                  ),
                ),
                if (_selectedCategory == _offersCategory)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SizedBox(
                              height: 132,
                              child: StorefrontOfferCard(
                                offer: _offers[index],
                                compact: true,
                                onAdd: () => _addOfferToCart(_offers[index]),
                              ),
                            ),
                          );
                        },
                        childCount: _offers.length,
                      ),
                    ),
                  )
                else if (filtered.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'لا توجد أصناف في هذا التصنيف',
                        style: TextStyle(
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
                      final pad = width >= 900 ? 20.0 : width >= 600 ? 12.0 : 10.0;
                      final gap = width >= 900 ? 14.0 : 8.0;

                      return SliverPadding(
                        padding: EdgeInsets.fromLTRB(pad, 4, pad, 16),
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: gap,
                            mainAxisSpacing: gap,
                            childAspectRatio: _gridChildAspect(columns),
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              return StorefrontItemCard(
                                item: filtered[index],
                                onAdd: () => _addToCart(filtered[index]),
                                dense: columns <= 2,
                              );
                            },
                            childCount: filtered.length,
                          ),
                        ),
                      );
                    },
                  ),
                if (_items.length < _total || _loadingMore)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                      child: Center(
                        child: _loadingMore
                            ? const CircularProgressIndicator(
                                color: AppTheme.brandOrange,
                              )
                            : TextButton(
                                onPressed: () => _loadItems(reset: false),
                                child: Text(
                                  'عرض المزيد (${_items.length}/$_total)',
                                ),
                              ),
                      ),
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

class _FloatingCartBar extends StatelessWidget {
  const _FloatingCartBar({
    required this.itemCount,
    required this.totalPrice,
    required this.cartItems,
    required this.onCheckout,
    required this.onAddSuggested,
    required this.restaurantId,
    this.settings,
  });

  final int itemCount;
  final double totalPrice;
  final List<CartItem> cartItems;
  final VoidCallback onCheckout;
  final ValueChanged<MenuItem> onAddSuggested;
  final String restaurantId;
  final RestaurantSettings? settings;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (settings != null && settings!.hasFreeDeliveryGoal)
                  FreeDeliveryProgressBar(
                    subtotal: totalPrice,
                    threshold: settings!.freeDeliveryThreshold,
                    baseDeliveryFee: 1,
                    strings: strings,
                  ),
                SmartSalesmanWidget(
                  compact: true,
                  cartItems: cartItems,
                  cartTotal: totalPrice,
                  restaurantId: restaurantId,
                  onAddItem: onAddSuggested,
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 360;
                    return FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.brandMaroon,
                        padding: EdgeInsets.symmetric(
                          vertical: narrow ? 12 : 14,
                          horizontal: narrow ? 12 : 20,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
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
                              'متابعة الطلب',
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
                                '${totalPrice.toStringAsFixed(3)} د.ك',
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
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;

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
            label: Text(
              category,
              overflow: TextOverflow.ellipsis,
            ),
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
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

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
            const Icon(
              Icons.cloud_off,
              size: 56,
              color: AppTheme.brandOrange,
            ),
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
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
