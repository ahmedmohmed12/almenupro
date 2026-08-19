import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/cart_item.dart';
import '../../models/menu_item.dart';
import '../../models/upsell_recommendation.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../network_menu_image.dart';

/// Stage 3 smart upsell strip for POS and customer cart.
class SmartSalesmanWidget extends StatefulWidget {
  const SmartSalesmanWidget({
    super.key,
    required this.cartItems,
    required this.onAddItem,
    this.cartTotal,
    this.restaurantId,
    this.compact = false,
  });

  final List<CartItem> cartItems;
  final ValueChanged<MenuItem> onAddItem;
  final double? cartTotal;
  final String? restaurantId;
  final bool compact;

  @override
  State<SmartSalesmanWidget> createState() => _SmartSalesmanWidgetState();
}

class _SmartSalesmanWidgetState extends State<SmartSalesmanWidget> {
  Timer? _debounce;
  var _loading = false;
  List<UpsellRecommendation> _recommendations = const [];

  String get _cartSignature => widget.cartItems
      .map((item) => '${item.menuItem.id}:${item.quantity}')
      .join(',');

  @override
  void initState() {
    super.initState();
    _scheduleFetch();
  }

  @override
  void didUpdateWidget(covariant SmartSalesmanWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldSignature = oldWidget.cartItems
        .map((item) => '${item.menuItem.id}:${item.quantity}')
        .join(',');
    if (oldSignature != _cartSignature ||
        oldWidget.cartTotal != widget.cartTotal) {
      _scheduleFetch();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _scheduleFetch() {
    _debounce?.cancel();
    if (widget.cartItems.isEmpty) {
      setState(() {
        _recommendations = const [];
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), _fetch);
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final payload = widget.cartItems
          .map(
            (item) => {
              'id': item.menuItem.id,
              'menuItemId': item.menuItem.id,
              'name': item.menuItem.name,
              'nameAr': item.menuItem.nameAr,
              'name_ar': item.menuItem.nameAr,
              'nameEn': item.menuItem.nameEn,
              'categoryName': item.menuItem.categoryName,
              'category_name': item.menuItem.categoryName,
              'price': item.menuItem.price,
              'quantity': item.quantity,
            },
          )
          .toList();
      final result = await ApiService.instance.fetchSmartUpsell(
        cartItems: payload,
        cartTotal: widget.cartTotal,
        restaurantId: widget.restaurantId,
      );
      if (!mounted) return;
      setState(() {
        _recommendations = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cartItems.isEmpty) return const SizedBox.shrink();
    if (!_loading && _recommendations.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.brandMaroon.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppTheme.brandMaroon, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'البياع الشاطر',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.brandMaroon,
                  ),
                ),
              ),
              if (_loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'اقتراحات لتكبير السلة بإضافة واحدة',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 10),
          ..._recommendations.map(_buildRow),
        ],
      ),
    );
  }

  Widget _buildRow(UpsellRecommendation recommendation) {
    final item = recommendation.item;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 320;
              final addButton = FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.brandMaroon,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  minimumSize: stacked
                      ? const Size.fromHeight(40)
                      : const Size(0, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                onPressed: () => widget.onAddItem(item),
                child: const Text('إضافة'),
              );
              final details = Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: widget.compact ? 40 : 48,
                      height: widget.compact ? 40 : 48,
                      child: item.imageUrl.trim().isEmpty
                          ? const ColoredBox(
                              color: Color(0xFFF4ECE9),
                              child: Icon(Icons.restaurant, size: 18),
                            )
                          : NetworkMenuImage(
                              imageUrl: item.imageUrl,
                              fit: BoxFit.cover,
                              width: 48,
                              height: 48,
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.localizedName('ar'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          recommendation.reasonLabel('ar'),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        Text(
                          '${item.price.toStringAsFixed(3)} د.ك',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.brandMaroon,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    details,
                    const SizedBox(height: 8),
                    addButton,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: details),
                  const SizedBox(width: 8),
                  addButton,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
