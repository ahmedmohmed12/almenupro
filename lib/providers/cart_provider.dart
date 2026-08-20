import 'package:flutter/foundation.dart';

import '../models/cart_item.dart';
import '../models/menu_item.dart';
import '../models/offer.dart';

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];
  Offer? _appliedOffer;

  String? _boundRestaurantId;

  List<CartItem> get items => List.unmodifiable(_items);

  Offer? get appliedOffer => _appliedOffer;

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  double get listSubtotal =>
      _items.fold(0, (sum, item) => sum + item.listedTotalPrice);

  double get itemsTotal =>
      _items.fold(0, (sum, item) => sum + item.totalPrice);

  double get lineDiscountTotal {
    final listed = listSubtotal;
    final charged = itemsTotal;
    return listed > charged ? listed - charged : 0;
  }

  double get cartLevelDiscount {
    final offer = _appliedOffer;
    if (offer == null || !offer.isCartLevel) return 0;
    return offer.cartDiscountFor(itemsTotal);
  }

  double get offerDiscountTotal => lineDiscountTotal + cartLevelDiscount;

  double get totalPrice {
    final next = itemsTotal - cartLevelDiscount;
    return next < 0 ? 0 : next;
  }

  bool get isEmpty => _items.isEmpty;

  void bindRestaurant(String restaurantId) {
    if (restaurantId.isEmpty) return;
    final switched = _boundRestaurantId != null &&
        _boundRestaurantId != restaurantId;
    if (switched && _items.isNotEmpty) {
      _items.clear();
      _appliedOffer = null;
    }
    _boundRestaurantId = restaurantId;
    if (switched) notifyListeners();
  }

  void addMenuItem(
    MenuItem menuItem, {
    int quantity = 1,
    String? offerId,
    double? originalUnitPrice,
    List<int> bundleItemIds = const [],
  }) {
    final existingIndex = _items.indexWhere(
      (item) =>
          item.menuItem.id == menuItem.id &&
          item.offerId == offerId &&
          item.selectedOptions.isEmpty,
    );

    if (existingIndex != -1) {
      final existing = _items[existingIndex];
      _items[existingIndex] = existing.copyWith(
        quantity: existing.quantity + quantity,
      );
    } else {
      _items.add(
        CartItem(
          id: '${menuItem.id}_${DateTime.now().microsecondsSinceEpoch}',
          menuItem: menuItem,
          selectedOptions: const [],
          quantity: quantity,
          offerId: offerId,
          originalUnitPrice: originalUnitPrice,
          bundleItemIds: bundleItemIds,
        ),
      );
    }
    notifyListeners();
  }

  void addItem({
    required MenuItem menuItem,
    required List<SelectedOption> selectedOptions,
    required int quantity,
    String? specialNotes,
  }) {
    _items.add(
      CartItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        menuItem: menuItem,
        selectedOptions: selectedOptions,
        quantity: quantity,
        specialNotes: specialNotes,
      ),
    );
    notifyListeners();
  }

  void removeItem(String cartItemId) {
    _items.removeWhere((item) => item.id == cartItemId);
    notifyListeners();
  }

  void updateQuantity(String cartItemId, int quantity) {
    if (quantity <= 0) {
      removeItem(cartItemId);
      return;
    }

    final index = _items.indexWhere((item) => item.id == cartItemId);
    if (index == -1) {
      return;
    }

    _items[index] = _items[index].copyWith(quantity: quantity);
    notifyListeners();
  }

  void applyOfferToCart(Offer offer, List<MenuItem> catalog) {
    if (offer.isCartLevel) {
      _appliedOffer = offer;
      notifyListeners();
      return;
    }

    if (offer.isCombo) {
      final byId = {for (final item in catalog) item.id: item};
      final bundled = offer.itemIds
          .map((id) => byId[id])
          .whereType<MenuItem>()
          .toList();
      final original = offer.originalPrice > 0
          ? offer.originalPrice
          : bundled.fold<double>(0, (sum, item) => sum + item.price);
      final sale = offer.offerPrice > 0
          ? offer.offerPrice
          : (original > 0 ? offer.discountedUnitPrice(original) : 0.0);
      final imageUrl = offer.imageUrl.isNotEmpty
          ? offer.imageUrl
          : (bundled.isNotEmpty ? bundled.first.imageUrl : '');
      final bundleItem = MenuItem(
        id: bundled.isNotEmpty ? bundled.first.id : offer.syntheticItemId,
        categoryId: 0,
        categoryName: 'العروض والخصومات',
        name: offer.title,
        description: offer.description,
        nameAr: offer.title,
        price: sale,
        imageUrl: imageUrl,
        isAvailable: true,
      );
      addMenuItem(
        bundleItem,
        offerId: offer.id,
        originalUnitPrice: original > sale ? original : null,
        bundleItemIds: offer.itemIds,
      );
      return;
    }

    final targets = offer.itemIds.isEmpty
        ? catalog
        : catalog.where((item) => offer.itemIds.contains(item.id)).toList();
    if (targets.isEmpty) {
      _appliedOffer = offer;
      notifyListeners();
      return;
    }
    for (final item in targets.take(8)) {
      final sale = offer.discountedUnitPrice(item.price);
      addMenuItem(
        item.copyWith(price: sale),
        offerId: offer.id,
        originalUnitPrice: item.price > sale ? item.price : null,
      );
    }
  }

  void clear() {
    _items.clear();
    _appliedOffer = null;
    notifyListeners();
  }
}
