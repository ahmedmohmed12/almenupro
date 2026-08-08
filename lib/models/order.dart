import 'package:cloud_firestore/cloud_firestore.dart';

import 'cart_item.dart';
import 'delivery_address_details.dart';

enum OrderType {
  delivery,
  pickup;

  String get label => switch (this) {
        OrderType.delivery => 'Delivery',
        OrderType.pickup => 'Pickup',
      };

  static OrderType fromString(String? value) {
    return OrderType.values.firstWhere(
      (type) => type.name == value?.toLowerCase(),
      orElse: () => OrderType.delivery,
    );
  }
}

enum OrderStatus {
  pending,
  confirmed,
  preparing,
  ready,
  delivered,
  cancelled;

  static OrderStatus fromString(String? value) {
    return OrderStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => OrderStatus.pending,
    );
  }

  String get arabicLabel => switch (this) {
        OrderStatus.pending => 'طلب جديد',
        OrderStatus.confirmed => 'تم القبول',
        OrderStatus.preparing => 'في الطريق',
        OrderStatus.ready => 'جاهز للاستلام',
        OrderStatus.delivered => 'تم التوصيل',
        OrderStatus.cancelled => 'ملغي',
      };

  String? get nextActionLabel => switch (this) {
        OrderStatus.pending => 'قبول',
        OrderStatus.confirmed => 'في الطريق',
        OrderStatus.preparing => 'تم التوصيل',
        _ => null,
      };

  OrderStatus? get nextStatus => switch (this) {
        OrderStatus.pending => OrderStatus.confirmed,
        OrderStatus.confirmed => OrderStatus.preparing,
        OrderStatus.preparing => OrderStatus.delivered,
        _ => null,
      };

  /// Active orders shown under "الطلبات الجديدة".
  bool get isActiveForAdmin =>
      this == OrderStatus.pending ||
      this == OrderStatus.confirmed ||
      this == OrderStatus.preparing ||
      this == OrderStatus.ready;

  /// Completed orders shown under "الطلبات السابقة".
  bool get isArchivedForAdmin =>
      this == OrderStatus.delivered || this == OrderStatus.cancelled;
}

class OrderLineItem {
  const OrderLineItem({
    required this.menuItemId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    required this.selectedOptions,
    this.specialNotes,
  });

  final String menuItemId;
  final String name;
  final double unitPrice;
  final int quantity;
  final List<SelectedOption> selectedOptions;
  final String? specialNotes;

  double get lineTotal => unitPrice * quantity;

  factory OrderLineItem.fromMap(Map<String, dynamic> map) {
    final rawOptions = map['selectedOptions'] as List<dynamic>? ?? [];

    return OrderLineItem(
      menuItemId: map['menuItemId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      unitPrice: (map['unitPrice'] as num?)?.toDouble() ??
          (map['price'] as num?)?.toDouble() ??
          0,
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      selectedOptions: rawOptions
          .map((option) => SelectedOption.fromMap(option as Map<String, dynamic>))
          .toList(),
      specialNotes: map['specialNotes'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'menuItemId': menuItemId,
      'name': name,
      'unitPrice': unitPrice,
      'quantity': quantity,
      'selectedOptions': selectedOptions.map((option) => option.toMap()).toList(),
      if (specialNotes != null && specialNotes!.isNotEmpty)
        'specialNotes': specialNotes,
      'lineTotal': lineTotal,
    };
  }

  factory OrderLineItem.fromCartItem(CartItem cartItem) {
    return OrderLineItem(
      menuItemId: cartItem.menuItem.id.toString(),
      name: cartItem.menuItem.name,
      unitPrice: cartItem.unitPrice,
      quantity: cartItem.quantity,
      selectedOptions: cartItem.selectedOptions,
      specialNotes: cartItem.specialNotes,
    );
  }
}

class Order {
  const Order({
    required this.id,
    required this.customerName,
    required this.phone,
    required this.address,
    required this.items,
    required this.totalPrice,
    required this.orderType,
    required this.status,
    required this.createdAt,
    this.invoiceNumber,
    this.paymentMethod,
    this.subtotal,
    this.deliveryFee,
    this.governorate,
    this.areaName,
    this.deliveryZoneId,
    this.addressDetails = const DeliveryAddressDetails(),
    this.orderSource,
  });

  final String id;
  final String customerName;
  final String phone;
  final String address;
  final List<OrderLineItem> items;
  final double totalPrice;
  final OrderType orderType;
  final OrderStatus status;
  final DateTime createdAt;
  final String? invoiceNumber;
  final String? paymentMethod;
  final double? subtotal;
  final double? deliveryFee;
  final String? governorate;
  final String? areaName;
  final String? deliveryZoneId;
  final DeliveryAddressDetails addressDetails;
  final String? orderSource;

  factory Order.fromMap(String id, Map<String, dynamic> map) {
    final rawItems = map['items'] as List<dynamic>? ?? [];

    return Order(
      id: id,
      customerName: map['customerName'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      address: map['address'] as String? ?? '',
      items: rawItems
          .map((item) => OrderLineItem.fromMap(item as Map<String, dynamic>))
          .toList(),
      totalPrice: (map['totalPrice'] as num?)?.toDouble() ?? 0,
      orderType: OrderType.fromString(map['orderType'] as String?),
      status: OrderStatus.fromString(map['status'] as String?),
      createdAt: _parseDateTime(map['createdAt']),
      invoiceNumber: map['invoiceNumber']?.toString(),
      paymentMethod: map['paymentMethod']?.toString(),
      subtotal: (map['subtotal'] as num?)?.toDouble(),
      deliveryFee: (map['deliveryFee'] as num?)?.toDouble() ??
          (map['delivery_fee'] as num?)?.toDouble(),
      governorate: map['governorate']?.toString(),
      areaName: map['areaName']?.toString() ?? map['area_name']?.toString(),
      deliveryZoneId:
          map['deliveryZoneId']?.toString() ?? map['delivery_zone_id']?.toString(),
      addressDetails: DeliveryAddressDetails.fromMap(
        map['addressDetails'] as Map<String, dynamic>? ??
            map['address_details'] as Map<String, dynamic>?,
      ),
      orderSource:
          map['orderSource']?.toString() ?? map['order_source']?.toString(),
    );
  }

  Order copyWith({
    OrderStatus? status,
    String? invoiceNumber,
    String? paymentMethod,
    double? subtotal,
    double? deliveryFee,
    double? totalPrice,
  }) {
    return Order(
      id: id,
      customerName: customerName,
      phone: phone,
      address: address,
      items: items,
      totalPrice: totalPrice ?? this.totalPrice,
      orderType: orderType,
      status: status ?? this.status,
      createdAt: createdAt,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      subtotal: subtotal ?? this.subtotal,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      governorate: governorate,
      areaName: areaName,
      deliveryZoneId: deliveryZoneId,
      addressDetails: addressDetails,
      orderSource: orderSource,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerName': customerName,
      'phone': phone,
      'address': address,
      'items': items.map((item) => item.toMap()).toList(),
      'totalPrice': totalPrice,
      'orderType': orderType.label,
      'status': status.name,
      'createdAt': createdAt.toUtc().toIso8601String(),
      if (subtotal != null) 'subtotal': subtotal,
      if (deliveryFee != null) 'deliveryFee': deliveryFee,
      if (governorate != null && governorate!.isNotEmpty) 'governorate': governorate,
      if (areaName != null && areaName!.isNotEmpty) 'areaName': areaName,
      if (deliveryZoneId != null && deliveryZoneId!.isNotEmpty)
        'deliveryZoneId': deliveryZoneId,
      if (!addressDetails.isEmpty) 'addressDetails': addressDetails.toMap(),
      if (invoiceNumber != null && invoiceNumber!.isNotEmpty)
        'invoiceNumber': invoiceNumber,
      if (paymentMethod != null && paymentMethod!.isNotEmpty)
        'paymentMethod': paymentMethod,
      if (orderSource != null && orderSource!.isNotEmpty) 'orderSource': orderSource,
    };
  }

  bool get isDemoOrder => id.startsWith('demo-');

  static DateTime _parseDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is String) {
      return DateTime.parse(value).toUtc();
    }
    return DateTime.now().toUtc();
  }
}
