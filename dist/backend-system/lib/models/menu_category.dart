class MenuCategory {
  const MenuCategory({
    required this.id,
    required this.restaurantId,
    required this.name,
    this.nameEn = '',
    this.sortOrder = 0,
    this.isActive = true,
  });

  final String id;
  final String restaurantId;
  final String name;
  final String nameEn;
  final int sortOrder;
  final bool isActive;

  String get nameAr => name;

  factory MenuCategory.fromMap(Map<String, dynamic> map) {
    return MenuCategory(
      id: map['id']?.toString() ?? '',
      restaurantId:
          map['restaurantId']?.toString() ??
          map['restaurant_id']?.toString() ??
          '',
      name:
          (map['name_ar'] ?? map['nameAr'] ?? map['name'] ?? '').toString(),
      nameEn: (map['name_en'] ?? map['nameEn'] ?? '').toString(),
      sortOrder:
          (map['sort_order'] as num?)?.toInt() ??
          (map['sortOrder'] as num?)?.toInt() ??
          0,
      isActive: map['is_active'] != false && map['isActive'] != false,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'restaurantId': restaurantId,
        'restaurant_id': restaurantId,
        'name': name,
        'name_ar': name,
        'nameAr': name,
        'name_en': nameEn,
        'nameEn': nameEn,
        'sort_order': sortOrder,
        'sortOrder': sortOrder,
        'is_active': isActive,
        'isActive': isActive,
      };

  MenuCategory copyWith({
    String? id,
    String? restaurantId,
    String? name,
    String? nameEn,
    int? sortOrder,
    bool? isActive,
  }) {
    return MenuCategory(
      id: id ?? this.id,
      restaurantId: restaurantId ?? this.restaurantId,
      name: name ?? this.name,
      nameEn: nameEn ?? this.nameEn,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
    );
  }
}
