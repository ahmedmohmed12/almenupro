import 'package:almenupro/models/cart_item.dart';
import 'package:almenupro/models/menu_item.dart';
import 'package:almenupro/utils/kitchen_modification_delta.dart';
import 'package:flutter_test/flutter_test.dart';

CartItem _line({
  required String id,
  required String name,
  required int qty,
  bool sent = true,
  String notes = '',
}) {
  return CartItem(
    id: id,
    menuItem: MenuItem(
      id: 1,
      categoryId: 1,
      categoryName: 'x',
      name: name,
      description: '',
      price: 1.0,
      imageUrl: '',
      isAvailable: true,
    ),
    selectedOptions: const [],
    quantity: qty,
    specialNotes: notes,
    isSentToKitchen: sent,
    sentToKitchenAt: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  test('detects void and add after kitchen send', () {
    final before = [_line(id: 'a', name: 'Laban', qty: 2)];
    final after = [_line(id: 'a', name: 'Laban', qty: 1)];
    final delta = computeKitchenModificationDelta(before, after);
    expect(delta.voided.length, 1);
    expect(delta.voided.first.quantity, 1);
    expect(delta.isEmpty, isFalse);
  });

  test('no delta before any kitchen send', () {
    final before = [_line(id: 'a', name: 'Tea', qty: 1, sent: false)];
    final after = [_line(id: 'a', name: 'Tea', qty: 2, sent: false)];
    final delta = computeKitchenModificationDelta(before, after);
    expect(delta.isEmpty, isTrue);
  });
}