class DeliveryZone {
  const DeliveryZone({
    required this.id,
    required this.governorate,
    required this.areaName,
    required this.deliveryFee,
    this.minOrder = 0,
    this.restaurantId,
    this.defaultKitchenId,
    this.isActive = true,
    this.driverDeliveryFee,
    this.platformMargin,
  });

  final String id;
  final String governorate;
  final String areaName;
  final double deliveryFee;
  /// Minimum cart subtotal (KWD) required before placing a delivery order.
  final double minOrder;
  final String? restaurantId;
  final String? defaultKitchenId;
  final bool isActive;
  final double? driverDeliveryFee;
  final double? platformMargin;

  String get displayName =>
      areaName.trim().isEmpty ? 'بدون اسم المنطقة' : areaName;

  String get displayGovernorate =>
      governorate.trim().isEmpty ? 'بدون محافظة' : governorate;

  static double _parseFee(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  factory DeliveryZone.fromMap(Map<String, dynamic> map) {
    return DeliveryZone(
      id: map['id']?.toString() ?? '',
      governorate: map['governorate']?.toString() ?? '',
      areaName: map['areaName']?.toString() ??
          map['area_name']?.toString() ??
          map['name']?.toString() ??
          '',
      deliveryFee: _parseFee(map['deliveryFee'] ?? map['delivery_fee'] ?? map['fee']),
      minOrder: _parseFee(
        map['minOrder'] ??
            map['min_order'] ??
            map['minimumOrder'] ??
            map['minimum_order'] ??
            0,
      ),
      restaurantId:
          map['restaurantId']?.toString() ?? map['restaurant_id']?.toString(),
      defaultKitchenId: map['defaultKitchenId']?.toString() ??
          map['default_kitchen_id']?.toString() ??
          map['kitchenId']?.toString() ??
          map['kitchen_id']?.toString(),
      isActive: map['isActive'] != false && map['is_active'] != false,
      driverDeliveryFee: map['driverDeliveryFee'] != null ||
              map['driver_delivery_fee'] != null
          ? _parseFee(map['driverDeliveryFee'] ?? map['driver_delivery_fee'])
          : null,
      platformMargin: map['platformMargin'] != null || map['platform_margin'] != null
          ? _parseFee(map['platformMargin'] ?? map['platform_margin'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'governorate': governorate,
      'areaName': areaName,
      'deliveryFee': deliveryFee,
      'minOrder': minOrder,
      'min_order': minOrder,
      if (restaurantId != null) 'restaurantId': restaurantId,
      if (restaurantId != null) 'restaurant_id': restaurantId,
      if (defaultKitchenId != null && defaultKitchenId!.isNotEmpty)
        'defaultKitchenId': defaultKitchenId,
      'isActive': isActive,
      if (driverDeliveryFee != null) 'driverDeliveryFee': driverDeliveryFee,
      if (driverDeliveryFee != null) 'driver_delivery_fee': driverDeliveryFee,
      if (platformMargin != null) 'platformMargin': platformMargin,
    };
  }

  DeliveryZone copyWith({
    String? governorate,
    String? areaName,
    double? deliveryFee,
    double? minOrder,
    String? restaurantId,
    String? defaultKitchenId,
    bool? isActive,
    double? driverDeliveryFee,
    double? platformMargin,
  }) {
    return DeliveryZone(
      id: id,
      governorate: governorate ?? this.governorate,
      areaName: areaName ?? this.areaName,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      minOrder: minOrder ?? this.minOrder,
      restaurantId: restaurantId ?? this.restaurantId,
      defaultKitchenId: defaultKitchenId ?? this.defaultKitchenId,
      isActive: isActive ?? this.isActive,
      driverDeliveryFee: driverDeliveryFee ?? this.driverDeliveryFee,
      platformMargin: platformMargin ?? this.platformMargin,
    );
  }
}
