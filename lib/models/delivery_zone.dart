class DeliveryZone {
  const DeliveryZone({
    required this.id,
    required this.governorate,
    required this.areaName,
    required this.deliveryFee,
    this.restaurantId,
    this.isActive = true,
  });

  final String id;
  final String governorate;
  final String areaName;
  final double deliveryFee;
  final String? restaurantId;
  final bool isActive;

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
      isActive: map['isActive'] != false && map['is_active'] != false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'governorate': governorate,
      'areaName': areaName,
      'deliveryFee': deliveryFee,
      if (restaurantId != null) 'restaurantId': restaurantId,
      'isActive': isActive,
    };
  }

  DeliveryZone copyWith({
    String? governorate,
    String? areaName,
    double? deliveryFee,
    bool? isActive,
  }) {
    return DeliveryZone(
      id: id,
      governorate: governorate ?? this.governorate,
      areaName: areaName ?? this.areaName,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      restaurantId: restaurantId,
      isActive: isActive ?? this.isActive,
    );
  }
}
