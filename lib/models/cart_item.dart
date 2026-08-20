import 'menu_item.dart';

class SelectedOption {
  const SelectedOption({
    required this.group,
    required this.name,
    required this.price,
  });

  final String group;
  final String name;
  final double price;

  factory SelectedOption.fromMap(Map<String, dynamic> map) {
    return SelectedOption(
      group: map['group'] as String? ?? '',
      name: map['name'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'group': group,
      'name': name,
      'price': price,
    };
  }
}

class CartItem {
  CartItem({
    required this.id,
    required this.menuItem,
    required this.selectedOptions,
    required this.quantity,
    this.specialNotes,
    this.offerId,
    this.originalUnitPrice,
    this.bundleItemIds = const [],
  });

  final String id;
  final MenuItem menuItem;
  final List<SelectedOption> selectedOptions;
  final int quantity;
  final String? specialNotes;
  final String? offerId;
  final double? originalUnitPrice;
  final List<int> bundleItemIds;

  double get unitPrice {
    final modifiers =
        selectedOptions.fold<double>(0, (sum, option) => sum + option.price);
    return menuItem.price + modifiers;
  }

  double get listedUnitPrice => originalUnitPrice ?? unitPrice;

  double get totalPrice => unitPrice * quantity;

  double get listedTotalPrice => listedUnitPrice * quantity;

  bool get hasOfferPrice =>
      originalUnitPrice != null && originalUnitPrice! > unitPrice + 0.0005;

  CartItem copyWith({
    String? id,
    MenuItem? menuItem,
    List<SelectedOption>? selectedOptions,
    int? quantity,
    String? specialNotes,
    String? offerId,
    double? originalUnitPrice,
    List<int>? bundleItemIds,
  }) {
    return CartItem(
      id: id ?? this.id,
      menuItem: menuItem ?? this.menuItem,
      selectedOptions: selectedOptions ?? this.selectedOptions,
      quantity: quantity ?? this.quantity,
      specialNotes: specialNotes ?? this.specialNotes,
      offerId: offerId ?? this.offerId,
      originalUnitPrice: originalUnitPrice ?? this.originalUnitPrice,
      bundleItemIds: bundleItemIds ?? this.bundleItemIds,
    );
  }
}
