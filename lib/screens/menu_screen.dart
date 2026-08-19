import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/menu_item.dart';
import '../providers/cart_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/menu/menu_checkout_sheet.dart';
import '../widgets/network_menu_image.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  static const _pageSize = 24;
  List<MenuItem> _items = [];
  var _loading = true;
  var _loadingMore = false;
  var _retrying = false;
  var _total = 0;
  String? _error;
  String _selectedCategory = 'الكل';

  @override
  void initState() {
    super.initState();
    _loadItems(autoRetry: true);
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
      final page = await ApiService.instance.fetchItemsPage(
        lite: true,
        limit: _pageSize,
        offset: reset ? 0 : _items.length,
      );
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
          final page = await ApiService.instance.fetchItemsPage(
            lite: true,
            limit: _pageSize,
            offset: 0,
          );
          if (!mounted) return;
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
    final categories = <String>{'الكل'};
    for (final item in items) {
      if (item.categoryName.trim().isNotEmpty) {
        categories.add(item.categoryName.trim());
      }
    }
    return categories.toList();
  }

  List<MenuItem> _filteredItems(List<MenuItem> items) {
    if (_selectedCategory == 'الكل') return items;
    return items
        .where((item) => item.categoryName.trim() == _selectedCategory)
        .toList();
  }

  int _gridColumns(double width) {
    if (width >= 1200) return 4;
    if (width >= 900) return 3;
    if (width >= 600) return 2;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.brandBackground,
        body: _buildBody(),
        bottomNavigationBar: cart.isEmpty
            ? null
            : _FloatingCartBar(
                itemCount: cart.itemCount,
                totalPrice: cart.totalPrice,
                onCheckout: () => MenuCheckoutSheet.show(context),
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
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _retrying
                          ? 'جاري تحديث المنيو...'
                          : 'تعذر التحديث. يمكنك متابعة التصفح.',
                      style: const TextStyle(fontSize: 13),
                    ),
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
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _MenuHeader(onRefresh: () => _loadItems()),
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
                if (filtered.isEmpty)
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
                      final cardWidth =
                          (width - 32 - (columns - 1) * 16) / columns;

                      return SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: cardWidth,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            mainAxisExtent: columns >= 3 ? 320 : 300,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              return _MenuItemCard(
                                item: filtered[index],
                                onAddToCart: () => _addToCart(filtered[index]),
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
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
    required this.onCheckout,
  });

  final int itemCount;
  final double totalPrice;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.brandMaroon,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          onPressed: onCheckout,
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
              const Expanded(
                child: Text(
                  'متابعة الطلب',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${totalPrice.toStringAsFixed(3)} د.ك',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      decoration: const BoxDecoration(
        color: AppTheme.brandSurface,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE8E0D8), width: 1),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.brandOrange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.cookie_outlined,
                color: AppTheme.brandOrange,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Molten Cookies',
                    style: TextStyle(
                      color: AppTheme.brandBlack,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'قائمة الطعام — ميني بايتس وكوكيز',
                    style: TextStyle(
                      color: Color(0xFF666666),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, color: AppTheme.brandOrange),
            ),
          ],
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
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = category == selected;

          return FilterChip(
            label: Text(category),
            selected: isSelected,
            showCheckmark: false,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : AppTheme.brandBlack,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            backgroundColor: Colors.white,
            selectedColor: AppTheme.brandOrange,
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

class _MenuItemCard extends StatelessWidget {
  const _MenuItemCard({
    required this.item,
    required this.onAddToCart,
  });

  final MenuItem item;
  final VoidCallback onAddToCart;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onAddToCart,
        child: Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _MenuItemImage(imageUrl: item.imageUrl),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.brandBlack,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.description.isNotEmpty
                          ? item.description
                          : 'لا يوجد وصف',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF555555),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              _PriceBar(price: item.price, onAddToCart: onAddToCart),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceBar extends StatelessWidget {
  const _PriceBar({
    required this.price,
    required this.onAddToCart,
  });

  final double price;
  final VoidCallback onAddToCart;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.brandOrange,
      child: InkWell(
        onTap: onAddToCart,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(
                Icons.add_shopping_cart_outlined,
                color: Colors.white,
                size: 18,
              ),
              Text(
                '${price.toStringAsFixed(3)} د.ك',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItemImage extends StatelessWidget {
  const _MenuItemImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isEmpty) {
      return _placeholder();
    }

    return NetworkMenuImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: AppTheme.brandSurface,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.brandOrange,
          ),
        );
      },
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppTheme.brandSurface,
      alignment: Alignment.center,
      child: const Icon(
        Icons.cookie_outlined,
        size: 48,
        color: AppTheme.brandOrange,
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
