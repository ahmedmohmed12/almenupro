import '../models/loyalty_cashback.dart';
import '../models/payment_method_config.dart';
import '../models/pos_role.dart';
import '../models/sales_platform_config.dart';
import '../models/working_hours.dart';
import '../utils/whatsapp_phone.dart';

class RestaurantSettings {
  const RestaurantSettings({
    required this.whatsappNumber,
    required this.workingHours,
    this.whatsappCountryCode = WhatsAppPhone.defaultCountryCode,
    this.whatsappPhone = '',
    this.updatedAt,
    this.smartUpsellEnabled = true,
    this.smartRecommendationsEnabled = true,
    this.freeDeliveryThreshold = 0,
    this.impulseBumpItemIds = const [],
    this.impulseBumpMaxPrice = 2,
    this.smartCartUpsellEnabled = true,
    this.smartUpsellDrinksEnabled = true,
    this.smartUpsellSidesEnabled = true,
    this.smartUpsellDessertsEnabled = true,
    this.dessertUpsellThreshold = 5,
    this.cashbackType = CashbackType.percentage,
    this.cashbackValue = 0,
    this.minOrderForLoyalty = 0,
    this.paymentMethods = const [],
    this.salesPlatforms = const [],
    this.posRoles = const [],
    this.posAutoLockMinutes = 5,
    this.logoUrl = '',
    this.restaurantDescription = '',
    this.notificationEmail = '',
    this.notifyOnNewOrderEmail = true,
    this.notifyOnShiftCloseEmail = false,
  });

  final String whatsappNumber;
  final String whatsappCountryCode;
  final String whatsappPhone;
  final WorkingHoursSettings workingHours;
  final DateTime? updatedAt;
  final bool smartUpsellEnabled;
  final bool smartRecommendationsEnabled;
  /// Minimum cart subtotal for free delivery. `0` disables the feature.
  final double freeDeliveryThreshold;
  final List<int> impulseBumpItemIds;
  /// Used to auto-pick impulse items when [impulseBumpItemIds] is empty.
  final double impulseBumpMaxPrice;
  /// Stage 3: complementary cart suggestions (drinks / sides / desserts).
  final bool smartCartUpsellEnabled;
  final bool smartUpsellDrinksEnabled;
  final bool smartUpsellSidesEnabled;
  final bool smartUpsellDessertsEnabled;
  /// Cart subtotal that unlocks dessert suggestions.
  final double dessertUpsellThreshold;
  final CashbackType cashbackType;
  final double cashbackValue;
  final double minOrderForLoyalty;
  final List<PaymentMethodConfig> paymentMethods;
  final List<SalesPlatformConfig> salesPlatforms;
  final List<PosRole> posRoles;
  final int posAutoLockMinutes;
  final String logoUrl;
  final String restaurantDescription;
  final String notificationEmail;
  final bool notifyOnNewOrderEmail;
  final bool notifyOnShiftCloseEmail;

  List<PaymentMethodConfig> get configuredPaymentMethods =>
      PaymentMethodCatalog.mergeWithDefaults(paymentMethods);

  List<SalesPlatformConfig> get resolvedSalesPlatforms =>
      PlatformCatalog.mergeWithDefaults(salesPlatforms);

  List<PosRole> get resolvedPosRoles =>
      posRoles.isEmpty ? PosRole.defaults() : posRoles;

  String get fullWhatsappNumber {
    final combined = WhatsAppPhone.combine(whatsappCountryCode, whatsappPhone);
    if (combined.isNotEmpty) return combined;
    return WhatsAppPhone.digitsOnly(whatsappNumber);
  }

  bool get hasWhatsappNumber => fullWhatsappNumber.isNotEmpty;

  bool get hasFreeDeliveryGoal =>
      smartUpsellEnabled && freeDeliveryThreshold > 0;

  factory RestaurantSettings.defaults() {
    return RestaurantSettings(
      whatsappCountryCode: WhatsAppPhone.defaultCountryCode,
      whatsappPhone: '',
      whatsappNumber: '',
      workingHours: WorkingHoursSettings.defaults(),
    );
  }

  factory RestaurantSettings.fromJson(Map<String, dynamic> json) {
    final legacyNumber =
        json['whatsappNumber']?.toString() ?? json['whatsapp_number']?.toString() ?? '';
    final explicitCountry = WhatsAppPhone.digitsOnly(
      json['whatsappCountryCode']?.toString() ??
          json['whatsapp_country_code']?.toString() ??
          '',
    );
    final explicitPhone = WhatsAppPhone.digitsOnly(
      json['whatsappPhone']?.toString() ?? json['whatsapp_phone']?.toString() ?? '',
    );

    String countryCode = explicitCountry.isNotEmpty
        ? explicitCountry
        : WhatsAppPhone.defaultCountryCode;
    String phone = explicitPhone;
    String fullNumber = WhatsAppPhone.digitsOnly(legacyNumber);

    if (phone.isNotEmpty) {
      fullNumber = WhatsAppPhone.combine(countryCode, phone);
    } else if (fullNumber.isNotEmpty) {
      final split = WhatsAppPhone.split(fullNumber);
      countryCode = split.countryCode;
      phone = split.phone;
    }

    final rawBumpIds = json['impulseBumpItemIds'] as List<dynamic>? ??
        json['impulse_bump_item_ids'] as List<dynamic>? ??
        [];

    return RestaurantSettings(
      whatsappCountryCode: countryCode,
      whatsappPhone: phone,
      whatsappNumber: fullNumber,
      workingHours: WorkingHoursSettings.fromJsonList(
        json['workingHours'] as List<dynamic>? ??
            json['working_hours'] as List<dynamic>?,
      ),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      smartUpsellEnabled: json['smartUpsellEnabled'] != false,
      smartRecommendationsEnabled: json['smartRecommendationsEnabled'] != false &&
          json['smart_recommendations_enabled'] != false,
      freeDeliveryThreshold:
          (json['freeDeliveryThreshold'] as num?)?.toDouble() ??
              (json['free_delivery_threshold'] as num?)?.toDouble() ??
              0,
      impulseBumpItemIds: rawBumpIds
          .map((id) => int.tryParse(id.toString()))
          .whereType<int>()
          .toList(),
      impulseBumpMaxPrice:
          (json['impulseBumpMaxPrice'] as num?)?.toDouble() ??
              (json['impulse_bump_max_price'] as num?)?.toDouble() ??
              2,
      smartCartUpsellEnabled: json['smartCartUpsellEnabled'] != false &&
          json['smart_cart_upsell_enabled'] != false,
      smartUpsellDrinksEnabled: json['smartUpsellDrinksEnabled'] != false &&
          json['smart_upsell_drinks_enabled'] != false,
      smartUpsellSidesEnabled: json['smartUpsellSidesEnabled'] != false &&
          json['smart_upsell_sides_enabled'] != false,
      smartUpsellDessertsEnabled: json['smartUpsellDessertsEnabled'] != false &&
          json['smart_upsell_desserts_enabled'] != false,
      dessertUpsellThreshold:
          (json['dessertUpsellThreshold'] as num?)?.toDouble() ??
              (json['dessert_upsell_threshold'] as num?)?.toDouble() ??
              5,
      cashbackType: CashbackType.fromStorage(
        json['cashbackType']?.toString() ?? json['cashback_type']?.toString(),
      ),
      cashbackValue: (json['cashbackValue'] as num?)?.toDouble() ??
          (json['cashback_value'] as num?)?.toDouble() ??
          0,
      minOrderForLoyalty: (json['minOrderForLoyalty'] as num?)?.toDouble() ??
          (json['min_order_for_loyalty'] as num?)?.toDouble() ??
          0,
      paymentMethods: _parsePaymentMethods(
        json['paymentMethods'] ?? json['payment_methods'],
      ),
      salesPlatforms: _parseSalesPlatforms(
        json['salesPlatforms'] ?? json['sales_platforms'],
      ),
      posRoles: _parsePosRoles(json['posRoles'] ?? json['pos_roles']),
      posAutoLockMinutes: (json['posAutoLockMinutes'] as num?)?.toInt() ??
          (json['pos_auto_lock_minutes'] as num?)?.toInt() ??
          5,
      logoUrl: json['logoUrl']?.toString() ?? json['logo_url']?.toString() ?? '',
      restaurantDescription: json['restaurantDescription']?.toString() ??
          json['restaurant_description']?.toString() ??
          json['description']?.toString() ??
          '',
      notificationEmail: json['notificationEmail']?.toString() ??
          json['notification_email']?.toString() ??
          '',
      notifyOnNewOrderEmail: json['notifyOnNewOrderEmail'] != false &&
          json['notify_on_new_order_email'] != false,
      notifyOnShiftCloseEmail: json['notifyOnShiftCloseEmail'] == true ||
          json['notify_on_shift_close_email'] == true,
    );
  }

  RestaurantSettings copyWith({
    String? whatsappNumber,
    String? whatsappCountryCode,
    String? whatsappPhone,
    WorkingHoursSettings? workingHours,
    DateTime? updatedAt,
    bool? smartUpsellEnabled,
    bool? smartRecommendationsEnabled,
    double? freeDeliveryThreshold,
    List<int>? impulseBumpItemIds,
    double? impulseBumpMaxPrice,
    bool? smartCartUpsellEnabled,
    bool? smartUpsellDrinksEnabled,
    bool? smartUpsellSidesEnabled,
    bool? smartUpsellDessertsEnabled,
    double? dessertUpsellThreshold,
    CashbackType? cashbackType,
    double? cashbackValue,
    double? minOrderForLoyalty,
    List<PaymentMethodConfig>? paymentMethods,
    List<SalesPlatformConfig>? salesPlatforms,
    List<PosRole>? posRoles,
    int? posAutoLockMinutes,
    String? logoUrl,
    String? restaurantDescription,
    String? notificationEmail,
    bool? notifyOnNewOrderEmail,
    bool? notifyOnShiftCloseEmail,
  }) {
    final nextCountry = whatsappCountryCode ?? this.whatsappCountryCode;
    final nextPhone = whatsappPhone ?? this.whatsappPhone;
    final nextFull = WhatsAppPhone.combine(nextCountry, nextPhone);

    return RestaurantSettings(
      whatsappCountryCode: nextCountry,
      whatsappPhone: nextPhone,
      whatsappNumber: nextFull.isNotEmpty
          ? nextFull
          : (whatsappNumber ?? this.whatsappNumber),
      workingHours: workingHours ?? this.workingHours,
      updatedAt: updatedAt ?? this.updatedAt,
      smartUpsellEnabled: smartUpsellEnabled ?? this.smartUpsellEnabled,
      smartRecommendationsEnabled:
          smartRecommendationsEnabled ?? this.smartRecommendationsEnabled,
      freeDeliveryThreshold: freeDeliveryThreshold ?? this.freeDeliveryThreshold,
      impulseBumpItemIds: impulseBumpItemIds ?? this.impulseBumpItemIds,
      impulseBumpMaxPrice: impulseBumpMaxPrice ?? this.impulseBumpMaxPrice,
      smartCartUpsellEnabled:
          smartCartUpsellEnabled ?? this.smartCartUpsellEnabled,
      smartUpsellDrinksEnabled:
          smartUpsellDrinksEnabled ?? this.smartUpsellDrinksEnabled,
      smartUpsellSidesEnabled:
          smartUpsellSidesEnabled ?? this.smartUpsellSidesEnabled,
      smartUpsellDessertsEnabled:
          smartUpsellDessertsEnabled ?? this.smartUpsellDessertsEnabled,
      dessertUpsellThreshold:
          dessertUpsellThreshold ?? this.dessertUpsellThreshold,
      cashbackType: cashbackType ?? this.cashbackType,
      cashbackValue: cashbackValue ?? this.cashbackValue,
      minOrderForLoyalty: minOrderForLoyalty ?? this.minOrderForLoyalty,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      salesPlatforms: salesPlatforms ?? this.salesPlatforms,
      posRoles: posRoles ?? this.posRoles,
      posAutoLockMinutes: posAutoLockMinutes ?? this.posAutoLockMinutes,
      logoUrl: logoUrl ?? this.logoUrl,
      restaurantDescription: restaurantDescription ?? this.restaurantDescription,
      notificationEmail: notificationEmail ?? this.notificationEmail,
      notifyOnNewOrderEmail: notifyOnNewOrderEmail ?? this.notifyOnNewOrderEmail,
      notifyOnShiftCloseEmail:
          notifyOnShiftCloseEmail ?? this.notifyOnShiftCloseEmail,
    );
  }

  Map<String, dynamic> toJson() => {
        'whatsappCountryCode': whatsappCountryCode,
        'whatsappPhone': whatsappPhone,
        'whatsappNumber': fullWhatsappNumber,
        'workingHours': workingHours.toJsonList(),
        'smartUpsellEnabled': smartUpsellEnabled,
        'smartRecommendationsEnabled': smartRecommendationsEnabled,
        'freeDeliveryThreshold': freeDeliveryThreshold,
        'impulseBumpItemIds': impulseBumpItemIds,
        'impulseBumpMaxPrice': impulseBumpMaxPrice,
        'smartCartUpsellEnabled': smartCartUpsellEnabled,
        'smartUpsellDrinksEnabled': smartUpsellDrinksEnabled,
        'smartUpsellSidesEnabled': smartUpsellSidesEnabled,
        'smartUpsellDessertsEnabled': smartUpsellDessertsEnabled,
        'dessertUpsellThreshold': dessertUpsellThreshold,
        'cashbackType': cashbackType.storageValue,
        'cashbackValue': cashbackValue,
        'minOrderForLoyalty': minOrderForLoyalty,
        'paymentMethods': paymentMethods.map((method) => method.toJson()).toList(),
        'salesPlatforms': salesPlatforms.map((platform) => platform.toJson()).toList(),
        'posRoles': posRoles.map((role) => role.toJson()).toList(),
        'posAutoLockMinutes': posAutoLockMinutes,
        'logoUrl': logoUrl,
        'restaurantDescription': restaurantDescription,
        'notificationEmail': notificationEmail,
        'notifyOnNewOrderEmail': notifyOnNewOrderEmail,
        'notifyOnShiftCloseEmail': notifyOnShiftCloseEmail,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };

  static List<PaymentMethodConfig> _parsePaymentMethods(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((entry) => PaymentMethodConfig.fromJson(Map<String, dynamic>.from(entry)))
        .toList();
  }

  static List<SalesPlatformConfig> _parseSalesPlatforms(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((entry) => SalesPlatformConfig.fromJson(Map<String, dynamic>.from(entry)))
        .where((platform) => platform.id.isNotEmpty)
        .toList();
  }

  static List<PosRole> _parsePosRoles(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((entry) => PosRole.fromJson(Map<String, dynamic>.from(entry)))
        .where((role) => role.id.isNotEmpty)
        .toList();
  }
}
