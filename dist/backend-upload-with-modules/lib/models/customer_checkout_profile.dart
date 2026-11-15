import 'delivery_address_details.dart';

class CustomerCheckoutProfile {
  const CustomerCheckoutProfile({
    required this.phone,
    required this.customerName,
    this.governorate = '',
    this.areaName = '',
    this.deliveryZoneId,
    this.addressDetails = const DeliveryAddressDetails(),
    this.paymentMethod = 'كاش',
    this.customerId,
    this.personalPromoCode = '',
    this.personalPromoDiscount = 0,
    this.walletBalance = 0,
    this.walletPromoCode = '',
  });

  final String phone;
  final String customerName;
  final String governorate;
  final String areaName;
  final String? deliveryZoneId;
  final DeliveryAddressDetails addressDetails;
  final String paymentMethod;
  final String? customerId;
  final String personalPromoCode;
  final double personalPromoDiscount;
  final double walletBalance;
  final String walletPromoCode;

  factory CustomerCheckoutProfile.fromMap(Map<String, dynamic> map) {
    final detailsRaw = map['addressDetails'] ?? map['address_details'];
    return CustomerCheckoutProfile(
      phone: map['phone']?.toString() ?? '',
      customerName:
          map['customerName']?.toString() ?? map['customer_name']?.toString() ?? '',
      governorate: map['governorate']?.toString() ?? '',
      areaName: map['areaName']?.toString() ?? map['area_name']?.toString() ?? '',
      deliveryZoneId:
          map['deliveryZoneId']?.toString() ?? map['delivery_zone_id']?.toString(),
      addressDetails: detailsRaw is Map<String, dynamic>
          ? DeliveryAddressDetails.fromMap(detailsRaw)
          : DeliveryAddressDetails.fromMap(
              detailsRaw is Map ? Map<String, dynamic>.from(detailsRaw) : null,
            ),
      paymentMethod:
          map['paymentMethod']?.toString() ?? map['payment_method']?.toString() ?? 'كاش',
      customerId: map['customerId']?.toString() ?? map['customer_id']?.toString(),
      personalPromoCode: map['personalPromoCode']?.toString() ??
          map['personal_promo_code']?.toString() ??
          '',
      personalPromoDiscount:
          (map['personalPromoDiscount'] as num?)?.toDouble() ??
              (map['personal_promo_discount'] as num?)?.toDouble() ??
              0,
      walletBalance: (map['walletBalance'] as num?)?.toDouble() ??
          (map['wallet_balance'] as num?)?.toDouble() ??
          0,
      walletPromoCode: map['walletPromoCode']?.toString() ??
          map['wallet_promo_code']?.toString() ??
          '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'phone': phone,
      'customerName': customerName,
      'governorate': governorate,
      'areaName': areaName,
      if (deliveryZoneId != null && deliveryZoneId!.isNotEmpty)
        'deliveryZoneId': deliveryZoneId,
      'addressDetails': addressDetails.toMap(),
      'paymentMethod': paymentMethod,
      if (customerId != null && customerId!.isNotEmpty) 'customerId': customerId,
      if (personalPromoCode.isNotEmpty) 'personalPromoCode': personalPromoCode,
      if (personalPromoDiscount > 0) 'personalPromoDiscount': personalPromoDiscount,
      if (walletBalance > 0) 'walletBalance': walletBalance,
      if (walletPromoCode.isNotEmpty) 'walletPromoCode': walletPromoCode,
    };
  }

  bool get hasUsableData =>
      customerName.trim().isNotEmpty ||
      addressDetails.block.trim().isNotEmpty ||
      addressDetails.street.trim().isNotEmpty ||
      governorate.trim().isNotEmpty ||
      areaName.trim().isNotEmpty;

  bool get hasActivePromo =>
      personalPromoCode.trim().isNotEmpty && personalPromoDiscount > 0;

  bool get hasWalletBalance => walletBalance > 0;
}
