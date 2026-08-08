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
  });

  final String phone;
  final String customerName;
  final String governorate;
  final String areaName;
  final String? deliveryZoneId;
  final DeliveryAddressDetails addressDetails;
  final String paymentMethod;

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
    };
  }

  bool get hasUsableData =>
      customerName.trim().isNotEmpty ||
      addressDetails.block.trim().isNotEmpty ||
      addressDetails.street.trim().isNotEmpty ||
      governorate.trim().isNotEmpty ||
      areaName.trim().isNotEmpty;
}
