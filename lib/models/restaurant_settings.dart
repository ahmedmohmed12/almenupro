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
    this.freeDeliveryThreshold = 0,
    this.impulseBumpItemIds = const [],
    this.impulseBumpMaxPrice = 2,
  });

  final String whatsappNumber;
  final String whatsappCountryCode;
  final String whatsappPhone;
  final WorkingHoursSettings workingHours;
  final DateTime? updatedAt;
  final bool smartUpsellEnabled;
  /// Minimum cart subtotal for free delivery. `0` disables the feature.
  final double freeDeliveryThreshold;
  final List<int> impulseBumpItemIds;
  /// Used to auto-pick impulse items when [impulseBumpItemIds] is empty.
  final double impulseBumpMaxPrice;

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
    );
  }

  RestaurantSettings copyWith({
    String? whatsappNumber,
    String? whatsappCountryCode,
    String? whatsappPhone,
    WorkingHoursSettings? workingHours,
    DateTime? updatedAt,
    bool? smartUpsellEnabled,
    double? freeDeliveryThreshold,
    List<int>? impulseBumpItemIds,
    double? impulseBumpMaxPrice,
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
      freeDeliveryThreshold: freeDeliveryThreshold ?? this.freeDeliveryThreshold,
      impulseBumpItemIds: impulseBumpItemIds ?? this.impulseBumpItemIds,
      impulseBumpMaxPrice: impulseBumpMaxPrice ?? this.impulseBumpMaxPrice,
    );
  }

  Map<String, dynamic> toJson() => {
        'whatsappCountryCode': whatsappCountryCode,
        'whatsappPhone': whatsappPhone,
        'whatsappNumber': fullWhatsappNumber,
        'workingHours': workingHours.toJsonList(),
        'smartUpsellEnabled': smartUpsellEnabled,
        'freeDeliveryThreshold': freeDeliveryThreshold,
        'impulseBumpItemIds': impulseBumpItemIds,
        'impulseBumpMaxPrice': impulseBumpMaxPrice,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };
}
