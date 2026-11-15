import '../models/cart_item.dart';
import '../models/menu_item.dart';
import '../models/order.dart';

List<CartItem> cartItemsFromOrderLines(
  Iterable<OrderLineItem> lines,
  List<MenuItem> menu,
) {
  final byId = <String, MenuItem>{
    for (final entry in menu) entry.id.toString(): entry,
  };
  return [
    for (final line in lines)
      CartItem(
        id: '${line.menuItemId}_${line.name}_${line.quantity}',
        menuItem: byId[line.menuItemId] ??
            MenuItem(
              id: int.tryParse(line.menuItemId) ?? line.name.hashCode,
              categoryId: 0,
              categoryName: '',
              name: line.name,
              description: '',
              price: line.unitPrice,
              imageUrl: '',
              isAvailable: true,
            ),
        selectedOptions: line.selectedOptions,
        quantity: line.quantity,
        specialNotes: line.specialNotes,
        offerId: line.offerId,
        originalUnitPrice: line.originalPrice,
      ),
  ];
}