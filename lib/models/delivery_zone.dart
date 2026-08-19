class DeliveryZone {
  const DeliveryZone({
    required this.id,
    required this.governorate,
    required this.areaName,
    required this.deliveryFee,
    this.restaurantId,
    this.defaultKitchenId,
    this.isActive = true,
  });

  final String id;
  final String governorate;
  final String areaName;
  final double deliveryFee;
  final String? restaurantId;
  final String? defaultKitchenId;
  final bool isActive;

  String get displayName =>
      areaName.trim().isEmpty ? 'بدون اسم المنطقة' : areaName;

  String get displayGovernorate =>
      governorate.trim().isEmpty ? 'بدون محافظة' : governorate;

  factory DeliveryZone.fromMap(Map<String, dynamic> map) {
    return DeliveryZone(
      id: map['id']?.toString() ?? '',
      governorate: map['governorate']?.toString() ?? '',
      areaName: map['areaName']?.toString() ?? map['area_name']?.toString() ?? '',
      deliveryFee: (map['deliveryFee'] as num?)?.toDouble() ??
          (map['delivery_fee'] as num?)?.toDouble() ??
          0,
      restaurantId:
          map['restaurantId']?.toString() ?? map['restaurant_id']?.toString(),
      defaultKitchenId: map['defaultKitchenId']?.toString() ??
          map['default_kitchen_id']?.toString() ??
          map['kitchenId']?.toString() ??
          map['kitchen_id']?.toString(),
      isActive: map['isActive'] != false && map['is_active'] != false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'governorate': governorate,
      'areaName': areaName,
      'deliveryFee': deliveryFee,
      if (restaurantId != null) 'restaurantId': restaurantId,
      if (restaurantId != null) 'restaurant_id': restaurantId,
      if (defaultKitchenId != null && defaultKitchenId!.isNotEmpty)
        'defaultKitchenId': defaultKitchenId,
      'isActive': isActive,
    };
  }

  DeliveryZone copyWith({
    String? governorate,
    String? areaName,
    double? deliveryFee,
    String? restaurantId,
    String? defaultKitchenId,
    bool? isActive,
  }) {
    return DeliveryZone(
      id: id,
      governorate: governorate ?? this.governorate,
      areaName: areaName ?? this.areaName,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      restaurantId: restaurantId ?? this.restaurantId,
      defaultKitchenId: defaultKitchenId ?? this.defaultKitchenId,
      isActive: isActive ?? this.isActive,
    );
  }
}
