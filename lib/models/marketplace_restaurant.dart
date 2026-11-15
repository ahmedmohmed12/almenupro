class MarketplaceCuisineTag {
  const MarketplaceCuisineTag({
    required this.id,
    required this.labelAr,
    required this.labelEn,
  });

  final String id;
  final String labelAr;
  final String labelEn;

  String label(bool isArabic) => isArabic ? labelAr : labelEn;

  factory MarketplaceCuisineTag.fromJson(Map<String, dynamic> json) {
    return MarketplaceCuisineTag(
      id: json['id']?.toString() ?? '',
      labelAr: json['labelAr']?.toString() ?? json['label_ar']?.toString() ?? '',
      labelEn: json['labelEn']?.toString() ?? json['label_en']?.toString() ?? '',
    );
  }
}

class MarketplaceCategory {
  const MarketplaceCategory({
    required this.id,
    required this.labelAr,
    required this.labelEn,
    this.icon = 'restaurant',
  });

  final String id;
  final String labelAr;
  final String labelEn;
  final String icon;

  String label(bool isArabic) => isArabic ? labelAr : labelEn;

  factory MarketplaceCategory.fromJson(Map<String, dynamic> json) {
    return MarketplaceCategory(
      id: json['id']?.toString() ?? '',
      labelAr: json['labelAr']?.toString() ?? json['label_ar']?.toString() ?? '',
      labelEn: json['labelEn']?.toString() ?? json['label_en']?.toString() ?? '',
      icon: json['icon']?.toString() ?? 'restaurant',
    );
  }
}

class MarketplaceRestaurant {
  const MarketplaceRestaurant({
    required this.id,
    required this.slug,
    required this.name,
    this.logoUrl = '',
    this.coverUrl = '',
    this.description = '',
    this.cuisines = const [],
    this.categoryIds = const ['all'],
    this.isOpen = true,
    this.rating = 0,
    this.reviewCount = 0,
    this.deliveryFee,
    this.deliveryTimeMin = 25,
    this.deliveryTimeMax = 35,
    this.promoLabel,
    this.freeDelivery = false,
    this.areas = const [],
  });

  final String id;
  final String slug;
  final String name;
  final String logoUrl;
  final String coverUrl;
  final String description;
  final List<MarketplaceCuisineTag> cuisines;
  final List<String> categoryIds;
  final bool isOpen;
  final double rating;
  final int reviewCount;
  final double? deliveryFee;
  final int deliveryTimeMin;
  final int deliveryTimeMax;
  final String? promoLabel;
  final bool freeDelivery;
  final List<String> areas;

  String get cuisineLine {
    final labels = cuisines.map((tag) => tag.labelAr).where((v) => v.isNotEmpty);
    return labels.take(3).join(' • ');
  }

  String get deliveryTimeLabel => '$deliveryTimeMin-$deliveryTimeMax min';

  String deliveryFeeLabel({required bool isArabic}) {
    if (deliveryFee == null) {
      return isArabic ? 'التوصيل حسب المنطقة' : 'Delivery by area';
    }
    if (deliveryFee! <= 0 || freeDelivery) {
      return isArabic ? 'توصيل مجاني' : 'Free delivery';
    }
    return '${deliveryFee!.toStringAsFixed(3)} ${isArabic ? 'د.ك' : 'KD'}';
  }

  factory MarketplaceRestaurant.fromJson(Map<String, dynamic> json) {
    final cuisineRaw = json['cuisines'];
    final cuisines = cuisineRaw is List
        ? cuisineRaw
            .whereType<Map>()
            .map(
              (row) => MarketplaceCuisineTag.fromJson(
                Map<String, dynamic>.from(row),
              ),
            )
            .toList()
        : const <MarketplaceCuisineTag>[];
    final categoryRaw = json['categoryIds'] ?? json['category_ids'];
    final categories = categoryRaw is List
        ? categoryRaw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : const <String>['all'];
    final areasRaw = json['areas'];
    final areas = areasRaw is List
        ? areasRaw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList()
        : const <String>[];

    return MarketplaceRestaurant(
      id: json['id']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      logoUrl: json['logoUrl']?.toString() ?? json['logo_url']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString() ??
          json['cover_url']?.toString() ??
          json['heroImageUrl']?.toString() ??
          '',
      description: json['description']?.toString() ?? '',
      cuisines: cuisines,
      categoryIds: categories.isEmpty ? const ['all'] : categories,
      isOpen: json['isOpen'] != false && json['is_open'] != false,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ??
          (json['review_count'] as num?)?.toInt() ??
          0,
      deliveryFee: json['deliveryFee'] == null && json['delivery_fee'] == null
          ? null
          : (json['deliveryFee'] as num?)?.toDouble() ??
              (json['delivery_fee'] as num?)?.toDouble(),
      deliveryTimeMin: (json['deliveryTimeMin'] as num?)?.toInt() ??
          (json['delivery_time_min'] as num?)?.toInt() ??
          25,
      deliveryTimeMax: (json['deliveryTimeMax'] as num?)?.toInt() ??
          (json['delivery_time_max'] as num?)?.toInt() ??
          35,
      promoLabel: (json['promoLabel'] ?? json['promo_label'])?.toString(),
      freeDelivery: json['freeDelivery'] == true || json['free_delivery'] == true,
      areas: areas,
    );
  }
}

class MarketplaceCatalog {
  const MarketplaceCatalog({
    this.categories = const [],
    this.areas = const [],
    this.restaurants = const [],
  });

  final List<MarketplaceCategory> categories;
  final List<String> areas;
  final List<MarketplaceRestaurant> restaurants;

  factory MarketplaceCatalog.fromJson(Map<String, dynamic> json) {
    final categoriesRaw = json['categories'];
    final restaurantsRaw = json['restaurants'];
    final areasRaw = json['areas'];
    return MarketplaceCatalog(
      categories: categoriesRaw is List
          ? categoriesRaw
              .whereType<Map>()
              .map(
                (row) => MarketplaceCategory.fromJson(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList()
          : const [],
      areas: areasRaw is List
          ? areasRaw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList()
          : const [],
      restaurants: restaurantsRaw is List
          ? restaurantsRaw
              .whereType<Map>()
              .map(
                (row) => MarketplaceRestaurant.fromJson(
                  Map<String, dynamic>.from(row),
                ),
              )
              .where((row) => row.slug.isNotEmpty)
              .toList()
          : const [],
    );
  }
}
