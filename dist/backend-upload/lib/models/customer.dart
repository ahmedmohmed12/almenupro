import 'delivery_address_details.dart';

class Customer {
  const Customer({
    required this.id,
    required this.phone,
    required this.customerName,
    required this.formattedAddress,
    this.governorate = '',
    this.areaName = '',
    this.deliveryZoneId,
    this.addressDetails = const DeliveryAddressDetails(),
    this.paymentMethod = 'كاش',
    this.totalOrders = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String phone;
  final String customerName;
  final String formattedAddress;
  final String governorate;
  final String areaName;
  final String? deliveryZoneId;
  final DeliveryAddressDetails addressDetails;
  final String paymentMethod;
  final int totalOrders;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Customer.fromMap(Map<String, dynamic> map) {
    final detailsRaw = map['addressDetails'] ?? map['address_details'];
    Map<String, dynamic>? detailsMap;
    if (detailsRaw is Map<String, dynamic>) {
      detailsMap = detailsRaw;
    } else if (detailsRaw is Map) {
      detailsMap = Map<String, dynamic>.from(detailsRaw);
    }

    final addressDetails = DeliveryAddressDetails.fromMap(detailsMap);
    final formattedAddress = map['formattedAddress']?.toString().trim().isNotEmpty == true
        ? map['formattedAddress'].toString()
        : map['address']?.toString() ?? '';

    return Customer(
      id: map['id']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      customerName:
          map['customerName']?.toString() ?? map['customer_name']?.toString() ?? '',
      formattedAddress: formattedAddress,
      governorate: map['governorate']?.toString() ?? '',
      areaName: map['areaName']?.toString() ?? map['area_name']?.toString() ?? '',
      deliveryZoneId:
          map['deliveryZoneId']?.toString() ?? map['delivery_zone_id']?.toString(),
      addressDetails: addressDetails,
      paymentMethod:
          map['paymentMethod']?.toString() ?? map['payment_method']?.toString() ?? 'كاش',
      totalOrders: (map['totalOrders'] as num?)?.toInt() ??
          (map['total_orders'] as num?)?.toInt() ??
          0,
      createdAt: _parseDate(map['createdAt'] ?? map['created_at']),
      updatedAt: _parseDate(map['updatedAt'] ?? map['updated_at']),
    );
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }
}

class CustomerDetailData {
  const CustomerDetailData({
    required this.customer,
    required this.rawOrders,
  });

  final Customer customer;
  final List<Map<String, dynamic>> rawOrders;

  factory CustomerDetailData.fromMap(Map<String, dynamic> map) {
    final customerRaw = map['customer'];
    final ordersRaw = map['orders'];

    return CustomerDetailData(
      customer: customerRaw is Map<String, dynamic>
          ? Customer.fromMap(customerRaw)
          : Customer.fromMap(
              customerRaw is Map ? Map<String, dynamic>.from(customerRaw) : const {},
            ),
      rawOrders: ordersRaw is List
          ? ordersRaw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : const [],
    );
  }
}
