import 'package:flutter/foundation.dart';

import '../models/cart_item.dart';
import '../models/menu_item.dart';

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  double get totalPrice =>
      _items.fold(0, (sum, item) => sum + item.totalPrice);

  bool get isEmpty => _items.isEmpty;

  void addMenuItem(MenuItem menuItem, {int quantity = 1}) {
    final existingIndex =
        _items.indexWhere((item) => item.menuItem.id == menuItem.id);

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

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
