enum OfferType {
  percentage,
  fixed,
  combo;

  static OfferType fromStorage(String? value) {
    switch (value?.toLowerCase()) {
      case 'fixed':
      case 'fixed_amount':
      case 'amount':
        return OfferType.fixed;
      case 'combo':
      case 'bundle':
        return OfferType.combo;
      default:
        return OfferType.percentage;
    }
  }

  String get storageValue => name;

  String get arabicLabel => switch (this) {
        OfferType.percentage => 'خصم نسبة',
        OfferType.fixed => 'خصم مبلغ ثابت',
        OfferType.combo => 'سعر كومبو',
      };
}

class Offer {
  const Offer({
    required this.id,
    required this.title,
    this.description = '',
    this.type = OfferType.percentage,
    this.discountValue = 0,
    this.originalPrice = 0,
    this.offerPrice = 0,
    this.itemIds = const [],
    this.imageUrl = '',
    this.badgeText = '',
    this.startsAt,
    this.endsAt,
    this.isActive = true,
    this.minSubtotal = 0,
    this.restaurantId,
  });

  final String id;
  final String title;
  final String description;
  final OfferType type;
  final double discountValue;
  final double originalPrice;
  final double offerPrice;
  final List<int> itemIds;
  final String imageUrl;
  final String badgeText;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool isActive;
  final double minSubtotal;
  final String? restaurantId;

  bool get isCombo => type == OfferType.combo;

  bool get isCartLevel => itemIds.isEmpty && !isCombo;

  String get displayBadge {
    if (badgeText.trim().isNotEmpty) return badgeText.trim();
    switch (type) {
      case OfferType.percentage:
        return '${discountValue.toStringAsFixed(0)}%';
      case OfferType.fixed:
        return '-${discountValue.toStringAsFixed(3)}';
      case OfferType.combo:
        return 'عرض';
    }
  }

  double get listPrice {
    if (originalPrice > 0) return originalPrice;
    return 0;
  }

  double get salePrice {
    if (type == OfferType.combo && offerPrice > 0) return offerPrice;
    if (originalPrice > 0) return discountedUnitPrice(originalPrice);
    return offerPrice;
  }

  bool get hasPricePair => listPrice > 0 && salePrice > 0 && salePrice < listPrice;

  bool get isLive {
    if (!isActive) return false;
    final now = DateTime.now().toUtc();
    if (startsAt != null && now.isBefore(startsAt!.toUtc())) return false;
    if (endsAt != null && now.isAfter(endsAt!.toUtc())) return false;
    return true;
  }

  double discountedUnitPrice(double original) {
    switch (type) {
      case OfferType.percentage:
        final pct = discountValue.clamp(0, 100);
        return (original * (1 - pct / 100)).clamp(0, original);
      case OfferType.fixed:
        return (original - discountValue).clamp(0, original);
      case OfferType.combo:
        return offerPrice > 0 ? offerPrice : original;
    }
  }

  double cartDiscountFor(double subtotal) {
    if (subtotal < minSubtotal) return 0;
    switch (type) {
      case OfferType.percentage:
        return (subtotal * (discountValue.clamp(0, 100) / 100)).clamp(0, subtotal);
      case OfferType.fixed:
        return discountValue.clamp(0, subtotal);
      case OfferType.combo:
        return 0;
    }
  }

  int get syntheticItemId {
    final hashed = id.hashCode.abs();
    return hashed == 0 ? 900001 : 900000 + (hashed % 90000);
  }

  factory Offer.fromMap(Map<String, dynamic> map) {
    return Offer(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      type: OfferType.fromStorage(map['type']?.toString()),
      discountValue: _num(map['discountValue'] ?? map['discount_value'] ?? map['value']),
      originalPrice: _num(map['originalPrice'] ?? map['original_price']),
      offerPrice: _num(map['offerPrice'] ?? map['offer_price'] ?? map['comboPrice']),
      itemIds: _ids(map['itemIds'] ?? map['item_ids'] ?? map['items']),
      imageUrl: map['imageUrl']?.toString() ?? map['image_url']?.toString() ?? '',
      badgeText: map['badgeText']?.toString() ?? map['badge_text']?.toString() ?? '',
      startsAt: _date(map['startsAt'] ?? map['starts_at'] ?? map['startDate']),
      endsAt: _date(map['endsAt'] ?? map['ends_at'] ?? map['endDate']),
      isActive: map['isActive'] != false && map['is_active'] != false,
      minSubtotal: _num(map['minSubtotal'] ?? map['min_subtotal']),
      restaurantId:
          map['restaurantId']?.toString() ?? map['restaurant_id']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'type': type.storageValue,
      'discountValue': discountValue,
      'originalPrice': originalPrice,
      'offerPrice': offerPrice,
      'itemIds': itemIds,
      'imageUrl': imageUrl,
      'badgeText': badgeText,
      if (startsAt != null) 'startsAt': startsAt!.toUtc().toIso8601String(),
      if (endsAt != null) 'endsAt': endsAt!.toUtc().toIso8601String(),
      'isActive': isActive,
      'minSubtotal': minSubtotal,
      if (restaurantId != null) 'restaurantId': restaurantId,
      if (restaurantId != null) 'restaurant_id': restaurantId,
    };
  }

  Offer copyWith({
    String? title,
    String? description,
    OfferType? type,
    double? discountValue,
    double? originalPrice,
    double? offerPrice,
    List<int>? itemIds,
    String? imageUrl,
    String? badgeText,
    DateTime? startsAt,
    DateTime? endsAt,
    bool? isActive,
    double? minSubtotal,
    String? restaurantId,
  }) {
    return Offer(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      type: type ?? this.type,
      discountValue: discountValue ?? this.discountValue,
      originalPrice: originalPrice ?? this.originalPrice,
      offerPrice: offerPrice ?? this.offerPrice,
      itemIds: itemIds ?? this.itemIds,
      imageUrl: imageUrl ?? this.imageUrl,
      badgeText: badgeText ?? this.badgeText,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      isActive: isActive ?? this.isActive,
      minSubtotal: minSubtotal ?? this.minSubtotal,
      restaurantId: restaurantId ?? this.restaurantId,
    );
  }

  static double _num(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _date(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static List<int> _ids(Object? value) {
    if (value is List) {
      return value
          .map((id) => int.tryParse(id.toString()) ?? 0)
          .where((id) => id > 0)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return value
          .split(RegExp(r'[,\s]+'))
          .map((id) => int.tryParse(id) ?? 0)
          .where((id) => id > 0)
          .toList();
    }
    return const [];
  }
}
