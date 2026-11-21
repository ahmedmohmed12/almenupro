import 'package:almenupro/models/cart_item.dart';
import 'package:almenupro/models/menu_item.dart';
import 'package:almenupro/utils/kitchen_dispatch.dart';
import 'package:flutter_test/flutter_test.dart';

CartItem _item({required int qty, bool sent = false}) {
  return CartItem(
    id: 'line_1',
    menuItem: MenuItem(
      id: 1,
      categoryId: 1,
      categoryName: 'Main',
      name: 'Test',
      description: '',
      price: 2.0,
      imageUrl: '',
      isAvailable: true,
    ),
    selectedOptions: const [],
    quantity: qty,
    isSentToKitchen: sent,
  );
}

void main() {
  test('increase quantity on kitchen-sent line needs no override', () {
    expect(
      cartMutationNeedsKitchenOverride(
        item: _item(qty: 2, sent: true),
        nextQuantity: 3,
      ),
      isFalse,
    );
  });

  test('unchanged kitchen-sent line needs no override', () {
    expect(
      cartMutationNeedsKitchenOverride(
        item: _item(qty: 2, sent: true),
        nextQuantity: 2,
      ),
      isFalse,
    );
  });

  test('unsent line never needs override', () {
    expect(
      cartMutationNeedsKitchenOverride(
        item: _item(qty: 2, sent: false),
        nextQuantity: 0,
      ),
      isFalse,
    );
  });
}