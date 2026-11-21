import 'package:cloud_firestore/cloud_firestore.dart';

import 'cart_item.dart';
import 'delivery_address_details.dart';
import 'order_payment_line.dart';

enum OrderType {
  delivery,
  pickup,
  dineIn,
  scheduledDelivery;

  String get label => switch (this) {
    OrderType.delivery => 'Delivery',
    OrderType.pickup => 'Pickup',
    OrderType.dineIn => 'صالة',
    OrderType.scheduledDelivery => 'توصيل مجدول',
  };

  String get storageValue => switch (this) {
    OrderType.scheduledDelivery => 'scheduled_delivery',
    _ => name,
  };

  static OrderType fromString(String? value) {
    final raw =
        value?.trim().toLowerCase().replaceAll('_', '').replaceAll('-', '') ??
        '';
    if (raw == 'pickup' || raw == 'takeaway') return OrderType.pickup;
    if (raw == 'dinein') return OrderType.dineIn;
    if (raw == 'scheduleddelivery') return OrderType.scheduledDelivery;
    return OrderType.delivery;
  }
}

enum OrderStatus {
  pending,
  confirmed,
  preparing,
  ready,
  delivered,
  cancelled,
  scheduled,
  inKitchen;

  static OrderStatus fromString(String? value) {
    final raw = (value ?? '').trim().toLowerCase().replaceAll('-', '_');
    if (raw == 'auto_accepted' ||
        raw == 'autoaccepted' ||
        raw == 'driver_pending') {
      return OrderStatus.confirmed;
    }
    if (raw == 'driver_accepted' || raw == 'on_the_way' || raw == 'picked_up') {
      return OrderStatus.preparing;
    }
    if (raw == 'in_kitchen' || raw == 'inkitchen') return OrderStatus.inKitchen;
    if (raw == 'scheduled') return OrderStatus.scheduled;
    return OrderStatus.values.firstWhere(
      (status) => status.name == raw || status.storageValue == raw,
      orElse: () => OrderStatus.pending,
    );
  }

  String get storageValue => switch (this) {
    OrderStatus.inKitchen => 'in_kitchen',
    _ => name,
  };

  String get arabicLabel => switch (this) {
    OrderStatus.pending => 'طلب جديد',
    OrderStatus.confirmed => 'تم القبول',
    OrderStatus.preparing => 'في الطريق',
    OrderStatus.ready => 'جاهز للاستلام',
    OrderStatus.delivered => 'تم التوصيل',
    OrderStatus.cancelled => 'ملغي',
    OrderStatus.scheduled => 'مجدول',
    OrderStatus.inKitchen => 'في المطبخ',
  };

  String? get nextActionLabel => switch (this) {
    OrderStatus.pending => 'قبول الأوردر',
    OrderStatus.confirmed => 'في الطريق',
    OrderStatus.preparing => 'تم التوصيل',
    OrderStatus.ready => 'تم التوصيل',
    OrderStatus.scheduled => null,
    OrderStatus.inKitchen => 'في الطريق',
    _ => null,
  };

  OrderStatus? get nextStatus => switch (this) {
    OrderStatus.pending => OrderStatus.confirmed,
    OrderStatus.confirmed => OrderStatus.preparing,
    OrderStatus.preparing => OrderStatus.delivered,
    OrderStatus.ready => OrderStatus.delivered,
    OrderStatus.scheduled => OrderStatus.inKitchen,
    OrderStatus.inKitchen => OrderStatus.preparing,
    _ => null,
  };

  bool get isInProgressForCashier =>
      this == OrderStatus.confirmed ||
      this == OrderStatus.preparing ||
      this == OrderStatus.ready ||
      this == OrderStatus.inKitchen;

  /// Active orders shown under "الطلبات الجديدة".
  bool get isActiveForAdmin =>
      this == OrderStatus.pending ||
      this == OrderStatus.confirmed ||
      this == OrderStatus.preparing ||
      this == OrderStatus.ready ||
      this == OrderStatus.inKitchen;

  /// Completed orders shown under "الطلبات السابقة".
  bool get isArchivedForAdmin =>
      this == OrderStatus.delivered || this == OrderStatus.cancelled;
}

class OrderStatusEvent {
  const OrderStatusEvent({required this.status, required this.timestamp});

  final String status;
  final DateTime timestamp;

  factory OrderStatusEvent.fromMap(Map<String, dynamic> map) {
    return OrderStatusEvent(
      status: map['status']?.toString() ?? '',
      timestamp: Order._parseDateTime(
        map['timestamp'] ?? map['at'] ?? map['createdAt'],
      ),
    );
  }

  Map<String, dynamic> toMap() => {
    'status': status,
    'timestamp': timestamp.toUtc().toIso8601String(),
  };
}

class OrderStatusTimeline {
  const OrderStatusTimeline({
    this.createdAt,
    this.acceptedAt,
    this.driverAssignedAt,
    this.pickedUpAt,
    this.onTheWayAt,
    this.deliveredAt,
    this.events = const [],
  });

  final DateTime? createdAt;
  final DateTime? acceptedAt;
  final DateTime? driverAssignedAt;
  final DateTime? pickedUpAt;
  final DateTime? onTheWayAt;
  final DateTime? deliveredAt;
  final List<OrderStatusEvent> events;

  DateTime? timeFor(String status) {
    switch (status) {
      case 'created_at':
        return createdAt;
      case 'accepted_at':
        return acceptedAt;
      case 'driver_assigned_at':
        return driverAssignedAt;
      case 'picked_up_at':
        return pickedUpAt;
      case 'on_the_way_at':
        return onTheWayAt;
      case 'delivered_at':
        return deliveredAt;
      default:
        for (final event in events) {
          if (event.status == status) return event.timestamp;
        }
        return null;
    }
  }

  Duration? get preparationDuration {
    if (acceptedAt == null || pickedUpAt == null) return null;
    return pickedUpAt!.difference(acceptedAt!);
  }

  Duration? get deliveryDuration {
    if (pickedUpAt == null || deliveredAt == null) return null;
    return deliveredAt!.difference(pickedUpAt!);
  }

  factory OrderStatusTimeline.fromMap(
    dynamic raw, {
    DateTime? fallbackCreatedAt,
  }) {
    DateTime? parseField(dynamic value) {
      if (value == null || (value is String && value.trim().isEmpty))
        return null;
      return Order._parseDateTime(value);
    }

    var createdAt = fallbackCreatedAt;
    DateTime? acceptedAt;
    DateTime? driverAssignedAt;
    DateTime? pickedUpAt;
    DateTime? onTheWayAt;
    DateTime? deliveredAt;
    final events = <OrderStatusEvent>[];

    if (raw is List) {
      for (final row in raw.whereType<Map>()) {
        final event = OrderStatusEvent.fromMap(Map<String, dynamic>.from(row));
        if (event.status.isEmpty) continue;
        events.add(event);
      }
    } else if (raw is Map) {
      createdAt =
          parseField(raw['created_at'] ?? raw['createdAt']) ?? createdAt;
      acceptedAt = parseField(raw['accepted_at'] ?? raw['acceptedAt']);
      driverAssignedAt = parseField(
        raw['driver_assigned_at'] ?? raw['driverAssignedAt'],
      );
      pickedUpAt = parseField(raw['picked_up_at'] ?? raw['pickedUpAt']);
      onTheWayAt = parseField(raw['on_the_way_at'] ?? raw['onTheWayAt']);
      deliveredAt = parseField(raw['delivered_at'] ?? raw['deliveredAt']);
      final nested = raw['events'];
      if (nested is List) {
        for (final row in nested.whereType<Map>()) {
          final event = OrderStatusEvent.fromMap(
            Map<String, dynamic>.from(row),
          );
          if (event.status.isEmpty) continue;
          events.add(event);
        }
      }
    }

    for (final event in events) {
      if (event.status == 'created_at') createdAt ??= event.timestamp;
      if (event.status == 'accepted_at') acceptedAt ??= event.timestamp;
      if (event.status == 'driver_assigned_at')
        driverAssignedAt ??= event.timestamp;
      if (event.status == 'picked_up_at') pickedUpAt ??= event.timestamp;
      if (event.status == 'on_the_way_at') onTheWayAt ??= event.timestamp;
      if (event.status == 'delivered_at') deliveredAt ??= event.timestamp;
    }

    createdAt ??= fallbackCreatedAt;
    if (createdAt != null &&
        events.every((event) => event.status != 'created_at')) {
      events.insert(
        0,
        OrderStatusEvent(status: 'created_at', timestamp: createdAt),
      );
    }

    return OrderStatusTimeline(
      createdAt: createdAt,
      acceptedAt: acceptedAt,
      driverAssignedAt: driverAssignedAt,
      pickedUpAt: pickedUpAt,
      onTheWayAt: onTheWayAt,
      deliveredAt: deliveredAt,
      events: events,
    );
  }

  OrderStatusTimeline stamp(String status, [DateTime? at]) {
    final timestamp = at ?? DateTime.now().toUtc();
    if (timeFor(status) != null) return this;
    final nextEvents = [
      ...events,
      OrderStatusEvent(status: status, timestamp: timestamp),
    ];
    return OrderStatusTimeline(
      createdAt: status == 'created_at' ? timestamp : createdAt,
      acceptedAt: status == 'accepted_at' ? timestamp : acceptedAt,
      driverAssignedAt: status == 'driver_assigned_at'
          ? timestamp
          : driverAssignedAt,
      pickedUpAt: status == 'picked_up_at' ? timestamp : pickedUpAt,
      onTheWayAt: status == 'on_the_way_at' ? timestamp : onTheWayAt,
      deliveredAt: status == 'delivered_at' ? timestamp : deliveredAt,
      events: nextEvents,
    );
  }

  OrderStatusTimeline stampForOrderStatus(
    OrderStatus status, {
    DateTime? createdAt,
  }) {
    var next = createdAt != null || this.createdAt != null
        ? stamp('created_at', this.createdAt ?? createdAt)
        : this;
    if (status == OrderStatus.confirmed) {
      next = next.stamp('accepted_at');
    }
    if (status == OrderStatus.delivered) {
      next = next.stamp('delivered_at');
    }
    return next;
  }

  Map<String, dynamic> toMap() => {
    if (createdAt != null) 'created_at': createdAt!.toUtc().toIso8601String(),
    if (acceptedAt != null)
      'accepted_at': acceptedAt!.toUtc().toIso8601String(),
    if (driverAssignedAt != null)
      'driver_assigned_at': driverAssignedAt!.toUtc().toIso8601String(),
    if (pickedUpAt != null)
      'picked_up_at': pickedUpAt!.toUtc().toIso8601String(),
    if (onTheWayAt != null)
      'on_the_way_at': onTheWayAt!.toUtc().toIso8601String(),
    if (deliveredAt != null)
      'delivered_at': deliveredAt!.toUtc().toIso8601String(),
    'events': events.map((event) => event.toMap()).toList(),
  };
}

class OrderLineItem {
  const OrderLineItem({
    this.id = '',
    required this.menuItemId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    required this.selectedOptions,
    this.specialNotes,
    this.offerId,
    this.originalPrice,
    this.isSentToKitchen = false,
    this.sentToKitchenAt,
  });

  final String id;
  final String menuItemId;
  final String name;
  final double unitPrice;
  final int quantity;
  final List<SelectedOption> selectedOptions;
  final String? specialNotes;
  final String? offerId;
  final double? originalPrice;
  final bool isSentToKitchen;
  final DateTime? sentToKitchenAt;

  double get lineTotal => unitPrice * quantity;

  factory OrderLineItem.fromMap(Map<String, dynamic> map) {
    final rawOptions = map['selectedOptions'] as List<dynamic>? ?? [];

    return OrderLineItem(
      id: map['id']?.toString() ?? '',
      menuItemId:
          map['menuItemId']?.toString() ??
          map['menu_item_id']?.toString() ??
          '',
      name: map['name']?.toString() ?? '',
      unitPrice:
          (map['unitPrice'] as num?)?.toDouble() ??
          (map['price'] as num?)?.toDouble() ??
          0,
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      selectedOptions: rawOptions
          .whereType<Map>()
          .map(
            (option) =>
                SelectedOption.fromMap(Map<String, dynamic>.from(option)),
          )
          .toList(),
      specialNotes: map['specialNotes']?.toString(),
      offerId: map['offerId']?.toString() ?? map['offer_id']?.toString(),
      originalPrice:
          (map['originalPrice'] as num?)?.toDouble() ??
          (map['original_price'] as num?)?.toDouble(),
      isSentToKitchen:
          map['isSentToKitchen'] == true || map['is_sent_to_kitchen'] == true,
      sentToKitchenAt: _parseKitchenAt(
        map['sentToKitchenAt'] ?? map['sent_to_kitchen_at'],
      ),
    );
  }

  static DateTime? _parseKitchenAt(Object? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toUtc();
  }

  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'menuItemId': menuItemId,
      'name': name,
      'unitPrice': unitPrice,
      'quantity': quantity,
      'selectedOptions': selectedOptions
          .map((option) => option.toMap())
          .toList(),
      if (specialNotes != null && specialNotes!.isNotEmpty)
        'specialNotes': specialNotes,
      if (offerId != null && offerId!.isNotEmpty) 'offerId': offerId,
      if (originalPrice != null) 'originalPrice': originalPrice,
      'lineTotal': lineTotal,
      'isSentToKitchen': isSentToKitchen,
      'is_sent_to_kitchen': isSentToKitchen,
      if (sentToKitchenAt != null)
        'sentToKitchenAt': sentToKitchenAt!.toIso8601String(),
      if (sentToKitchenAt != null)
        'sent_to_kitchen_at': sentToKitchenAt!.toIso8601String(),
    };
  }

  factory OrderLineItem.fromCartItem(CartItem cartItem) {
    return OrderLineItem(
      id: cartItem.id,
      menuItemId: cartItem.menuItem.id.toString(),
      name: cartItem.menuItem.name,
      unitPrice: cartItem.unitPrice,
      quantity: cartItem.quantity,
      selectedOptions: cartItem.selectedOptions,
      specialNotes: cartItem.specialNotes,
      offerId: cartItem.offerId,
      originalPrice: cartItem.originalUnitPrice,
      isSentToKitchen: cartItem.isSentToKitchen,
      sentToKitchenAt: cartItem.sentToKitchenAt,
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
    this.payments,
    this.subtotal,
    this.deliveryFee,
    this.governorate,
    this.areaName,
    this.deliveryZoneId,
    this.addressDetails = const DeliveryAddressDetails(),
    this.orderSource,
    this.storeName = '',
    this.ingestionSource = '',
    this.createdFromPos = false,
    this.shiftId,
    this.cashierId,
    this.cashierName,
    this.acceptedBy,
    this.acceptedByName,
    this.externalOrderId,
    this.platformCommission,
    this.customerPayableTotal,
    this.netMerchantSales,
    this.deliveryInstructions = '',
    this.priceLocked = false,
    this.walletRedeemAmount,
    this.discountAmount,
    this.offerId,
    this.offerTitle,
    this.targetKitchenId,
    this.targetKitchenName,
    this.assignedDriverId,
    this.assignedDriverName,
    this.assignedDriverPhone,
    this.deliveryStatus,
    this.deliveryRequestId,
    this.driverFee,
    this.cashierHandoffConfirmedAt,
    this.driverHandoffConfirmedAt,
    this.handshakeNetToCashier,
    this.handshakeCashierPaysDriver,
    this.handshakeCollectFromCustomer,
    this.statusTimeline = const OrderStatusTimeline(),
    this.rating,
    this.reviewNote,
    this.isRated = false,
    this.ratingToken,
    this.offlineTxId,
    this.tableId,
    this.tableNumber,
    this.deliveryDate,
    this.targetDeliveryTime,
    this.prepTimeMinutes,
    this.routeTimeMinutes,
    this.cashierBufferMinutes,
    this.autoReleaseTime,
    this.paymentStatus,
    this.paidAt,
    this.heldShiftId,
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
  final List<OrderPaymentLine>? payments;
  final double? subtotal;
  final double? deliveryFee;
  final String? governorate;
  final String? areaName;
  final String? deliveryZoneId;
  final DeliveryAddressDetails addressDetails;
  final String? orderSource;
  /// Branch or portal store that received the order. Shown in POS and admin only.
  final String storeName;
  final String ingestionSource;
  final bool createdFromPos;
  final String? shiftId;
  final String? cashierId;
  final String? cashierName;
  final String? acceptedBy;
  final String? acceptedByName;
  final String? externalOrderId;
  final double? platformCommission;
  final double? customerPayableTotal;
  final double? netMerchantSales;
  final String deliveryInstructions;
  final bool priceLocked;
  final double? walletRedeemAmount;
  final double? discountAmount;
  final String? offerId;
  final String? offerTitle;
  final String? targetKitchenId;
  final String? targetKitchenName;
  final String? assignedDriverId;
  final String? assignedDriverName;
  final String? assignedDriverPhone;
  final String? deliveryStatus;
  final String? deliveryRequestId;
  final double? driverFee;
  final DateTime? cashierHandoffConfirmedAt;
  final DateTime? driverHandoffConfirmedAt;
  final double? handshakeNetToCashier;
  final double? handshakeCashierPaysDriver;
  final double? handshakeCollectFromCustomer;
  final OrderStatusTimeline statusTimeline;
  final int? rating;
  final String? reviewNote;
  final bool isRated;
  final String? ratingToken;
  final String? offlineTxId;
  final String? tableId;
  final String? tableNumber;
  final DateTime? deliveryDate;
  final DateTime? targetDeliveryTime;
  final int? prepTimeMinutes;
  final int? routeTimeMinutes;
  final int? cashierBufferMinutes;
  final DateTime? autoReleaseTime;
  /// `pending_payment` for held pickup; `paid` or null after settlement.
  final String? paymentStatus;
  final DateTime? paidAt;
  /// Shift id when the order was held (audit); revenue uses [shiftId] after pay.
  final String? heldShiftId;

  DateTime? get resolvedAutoReleaseTime {
    if (autoReleaseTime != null) return autoReleaseTime;
    final target = targetDeliveryTime;
    if (target == null) return null;
    final lead =
        (prepTimeMinutes ?? 0) +
        (routeTimeMinutes ?? 0) +
        (cashierBufferMinutes ?? 0);
    return target.subtract(Duration(minutes: lead));
  }

  bool get hasAssignedDriver =>
      (assignedDriverId ?? '').trim().isNotEmpty ||
      (assignedDriverName ?? '').trim().isNotEmpty;

  /// Driver has accepted and the trip is still live (not delivered).
  bool get isHeldByDriver {
    if (orderType != OrderType.delivery) return false;
    if (status == OrderStatus.delivered || status == OrderStatus.cancelled) {
      return false;
    }
    if (isDriverCustodyDeliveryStatus(deliveryStatus)) return true;
    if (hasAssignedDriver &&
        (status == OrderStatus.preparing || status == OrderStatus.ready)) {
      return true;
    }
    return false;
  }

  static bool isDriverCustodyDeliveryStatus(String? raw) {
    final value = (raw ?? '').trim().toLowerCase().replaceAll('-', '_');
    return value == 'driver_accepted' ||
        value == 'picked_up' ||
        value == 'on_the_way' ||
        value == 'in_transit' ||
        value == 'accepted';
  }

  static const driverCustodyLockMessage =
      'الطلب بحوزة السائق - التحديث عبر تطبيق السائق فقط';

  static String _normalizedDeliveryStatus(String? raw) =>
      (raw ?? '').trim().toLowerCase().replaceAll('-', '_');

  bool get _hasLeftRestaurant {
    final delivery = _normalizedDeliveryStatus(deliveryStatus);
    return delivery == 'picked_up' ||
        delivery == 'on_the_way' ||
        delivery == 'in_transit' ||
        delivery == 'delivered' ||
        statusTimeline.pickedUpAt != null;
  }

  /// Driver accepted and is still coming to the restaurant (not picked up yet).
  bool get isAwaitingHandoff {
    if (orderType != OrderType.delivery) return false;
    if (status == OrderStatus.delivered || status == OrderStatus.cancelled) {
      return false;
    }
    if (_hasLeftRestaurant) return false;
    if (hasAssignedDriver) return true;
    return isDriverCustodyDeliveryStatus(deliveryStatus);
  }

  /// Cashier still needs to take cash or pay the driver fee before pickup.
  bool get needsCashierHandoff => isAwaitingHandoff && !cashierHandoffDone;

  bool get waitingDriverAfterCashierConfirm =>
      isAwaitingHandoff && cashierHandoffDone && !driverHandoffDone;

  bool get cashierHandoffDone => cashierHandoffConfirmedAt != null;
  bool get driverHandoffDone => driverHandoffConfirmedAt != null;

  bool get isWaitingDriver =>
      orderType == OrderType.delivery &&
      status == OrderStatus.confirmed &&
      !hasAssignedDriver;

  bool get isNewForCashier =>
      !createdFromPos && (status == OrderStatus.pending || isWaitingDriver);

  bool get isCurrentForCashier =>
      status == OrderStatus.preparing ||
      status == OrderStatus.ready ||
      status == OrderStatus.inKitchen ||
      (status == OrderStatus.confirmed && (createdFromPos || !isWaitingDriver));

  bool get isNewForAdmin =>
      !createdFromPos && (status == OrderStatus.pending || isWaitingDriver);

  bool get isCurrentForAdmin =>
      status == OrderStatus.preparing ||
      status == OrderStatus.ready ||
      status == OrderStatus.inKitchen ||
      (status == OrderStatus.confirmed && (createdFromPos || !isWaitingDriver));

  String get cashierStatusLabel {
    if (isWaitingDriver) return 'بانتظار السائق';
    final delivery = (deliveryStatus ?? '').trim().toLowerCase();
    if (delivery == 'on_the_way') return 'في الطريق للعميل';
    if (delivery == 'picked_up') return 'تم الاستلام';
    if (delivery == 'driver_accepted' && status == OrderStatus.preparing) {
      return 'السائق في الطريق للمطعم';
    }
    return status.arabicLabel;
  }

  String get receivedByCashierLabel {
    final name = cashierName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return acceptedByName?.trim() ?? '';
  }

  String get acceptedByLabel {
    final name = acceptedByName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return acceptedBy?.trim() ?? '';
  }

  double get netRevenue =>
      merchantSales - (platformCommission == null ? 0 : platformCommission!);

  double get customerPayable =>
      customerPayableTotal ?? totalPrice;

  double get merchantSales => netMerchantSales ?? (subtotal ?? totalPrice);

  bool get isPlatformPriceLocked {
    if (priceLocked) return true;
    final source = (orderSource ?? '').trim().toLowerCase();
    final external = (externalOrderId ?? '').trim().isNotEmpty;
    return external &&
        (source == 'talabat' ||
            source == 'keeta' ||
            source == 'keta' ||
            source == 'jahez');
  }

  bool get isCashOnDelivery {
    final value = (paymentMethod ?? '').toLowerCase();
    return value.contains('cash') ||
        value.contains('cod') ||
        value.contains('كاش') ||
        value.contains('نقد');
  }

  String get settlementLabel {
    final method = (paymentMethod ?? '').trim();
    if (method.isEmpty) return '';
    return isCashOnDelivery ? 'CASH ON DELIVERY' : 'PREPAID / ONLINE';
  }

  factory Order.fromMap(String id, Map<String, dynamic> map) {
    final rawItems = map['items'] as List<dynamic>? ?? [];

    return Order(
      id: id,
      customerName: map['customerName'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      address: map['address'] as String? ?? '',
      items: rawItems
          .whereType<Map>()
          .map((item) => OrderLineItem.fromMap(Map<String, dynamic>.from(item)))
          .toList(),
      totalPrice: (map['totalPrice'] as num?)?.toDouble() ?? 0,
      orderType: OrderType.fromString(map['orderType'] as String?),
      status: OrderStatus.fromString(map['status'] as String?),
      createdAt: _parseDateTime(map['createdAt']),
      invoiceNumber: map['invoiceNumber']?.toString(),
      paymentMethod: map['paymentMethod']?.toString(),
      payments: (map['payments'] as List<dynamic>?)
          ?.whereType<Map>()
          .map(
            (row) => OrderPaymentLine.fromMap(Map<String, dynamic>.from(row)),
          )
          .toList(),
      subtotal: (map['subtotal'] as num?)?.toDouble(),
      deliveryFee:
          (map['deliveryFee'] as num?)?.toDouble() ??
          (map['delivery_fee'] as num?)?.toDouble(),
      governorate: map['governorate']?.toString(),
      areaName: map['areaName']?.toString() ?? map['area_name']?.toString(),
      deliveryZoneId:
          map['deliveryZoneId']?.toString() ??
          map['delivery_zone_id']?.toString(),
      addressDetails: DeliveryAddressDetails.fromMap(
        map['addressDetails'] as Map<String, dynamic>? ??
            map['address_details'] as Map<String, dynamic>?,
      ),
      orderSource:
          map['orderSource']?.toString() ?? map['order_source']?.toString(),
      storeName:
          (map['storeName'] ?? map['store_name'] ?? '').toString().trim(),
      ingestionSource:
          map['ingestionSource']?.toString() ??
          map['ingestion_source']?.toString() ??
          '',
      createdFromPos:
          map['createdFromPos'] == true ||
          map['created_from_pos'] == true ||
          map['createdFromPos'] == 1 ||
          map['created_from_pos'] == 1,
      shiftId: map['shiftId']?.toString() ?? map['shift_id']?.toString(),
      cashierId: map['cashierId']?.toString() ?? map['cashier_id']?.toString(),
      cashierName:
          map['cashierName']?.toString() ?? map['cashier_name']?.toString(),
      acceptedBy:
          map['acceptedBy']?.toString() ?? map['accepted_by']?.toString(),
      acceptedByName:
          map['acceptedByName']?.toString() ??
          map['accepted_by_name']?.toString(),
      externalOrderId:
          map['externalOrderId']?.toString() ??
          map['external_order_id']?.toString(),
      platformCommission:
          (map['platformCommission'] as num?)?.toDouble() ??
          (map['platform_commission'] as num?)?.toDouble(),
      customerPayableTotal:
          (map['customerPayableTotal'] as num?)?.toDouble() ??
          (map['customer_payable_total'] as num?)?.toDouble(),
      netMerchantSales:
          (map['netMerchantSales'] as num?)?.toDouble() ??
          (map['net_merchant_sales'] as num?)?.toDouble(),
      deliveryInstructions:
          map['deliveryInstructions']?.toString() ??
          map['delivery_instructions']?.toString() ??
          '',
      priceLocked:
          map['priceLocked'] == true ||
          map['price_locked'] == true ||
          map['priceLocked'] == 1,
      walletRedeemAmount:
          (map['walletRedeemAmount'] as num?)?.toDouble() ??
          (map['wallet_redeem_amount'] as num?)?.toDouble() ??
          (map['walletRedeemed'] as num?)?.toDouble(),
      discountAmount:
          (map['discountAmount'] as num?)?.toDouble() ??
          (map['discount_amount'] as num?)?.toDouble(),
      offerId: map['offerId']?.toString() ?? map['offer_id']?.toString(),
      offerTitle:
          map['offerTitle']?.toString() ?? map['offer_title']?.toString(),
      targetKitchenId:
          map['targetKitchenId']?.toString() ??
          map['target_kitchen_id']?.toString(),
      targetKitchenName:
          map['targetKitchenName']?.toString() ??
          map['target_kitchen_name']?.toString(),
      assignedDriverId:
          map['assignedDriverId']?.toString() ??
          map['assigned_driver_id']?.toString(),
      assignedDriverName:
          map['assignedDriverName']?.toString() ??
          map['assigned_driver_name']?.toString(),
      assignedDriverPhone:
          map['assignedDriverPhone']?.toString() ??
          map['assigned_driver_phone']?.toString(),
      deliveryStatus:
          map['deliveryStatus']?.toString() ??
          map['delivery_status']?.toString(),
      deliveryRequestId:
          map['deliveryRequestId']?.toString() ??
          map['delivery_request_id']?.toString(),
      driverFee:
          (map['driverFee'] as num?)?.toDouble() ??
          (map['driver_fee'] as num?)?.toDouble() ??
          (map['assigned_driver_fee'] as num?)?.toDouble() ??
          (map['assignedDriverFee'] as num?)?.toDouble(),
      cashierHandoffConfirmedAt: _tryParseDateTime(
        map['cashier_handoff_confirmed_at'] ?? map['cashierHandoffConfirmedAt'],
      ),
      driverHandoffConfirmedAt: _tryParseDateTime(
        map['driver_handoff_confirmed_at'] ?? map['driverHandoffConfirmedAt'],
      ),
      handshakeNetToCashier:
          (map['handshake_net_to_cashier'] as num?)?.toDouble() ??
          (map['handshakeNetToCashier'] as num?)?.toDouble(),
      handshakeCashierPaysDriver:
          (map['handshake_cashier_pays_driver'] as num?)?.toDouble() ??
          (map['handshakeCashierPaysDriver'] as num?)?.toDouble(),
      handshakeCollectFromCustomer:
          (map['handshake_collect_from_customer'] as num?)?.toDouble() ??
          (map['handshakeCollectFromCustomer'] as num?)?.toDouble(),
      statusTimeline: OrderStatusTimeline.fromMap(
        {
          'created_at': map['created_at'] ?? map['createdAt'],
          'accepted_at': map['accepted_at'] ?? map['acceptedAt'],
          'driver_assigned_at':
              map['driver_assigned_at'] ?? map['driverAssignedAt'],
          'picked_up_at': map['picked_up_at'] ?? map['pickedUpAt'],
          'on_the_way_at': map['on_the_way_at'] ?? map['onTheWayAt'],
          'delivered_at': map['delivered_at'] ?? map['deliveredAt'],
          if (map['status_timeline'] is Map)
            ...Map<String, dynamic>.from(map['status_timeline'] as Map)
          else if (map['statusTimeline'] is Map)
            ...Map<String, dynamic>.from(map['statusTimeline'] as Map)
          else if (map['status_timeline'] is List)
            'events': map['status_timeline']
          else if (map['statusTimeline'] is List)
            'events': map['statusTimeline'],
        },
        fallbackCreatedAt: _parseDateTime(
          map['createdAt'] ?? map['created_at'],
        ),
      ),
      rating: (map['rating'] as num?)?.toInt(),
      reviewNote:
          map['reviewNote']?.toString() ?? map['review_note']?.toString(),
      isRated:
          map['isRated'] == true ||
          map['is_rated'] == true ||
          ((map['rating'] as num?)?.toInt() ?? 0) >= 1,
      ratingToken:
          map['ratingToken']?.toString() ?? map['rating_token']?.toString(),
      offlineTxId:
          map['offlineTxId']?.toString() ??
          map['offline_tx_id']?.toString() ??
          (id.startsWith('offline_tx_') ? id : null),
      tableId: map['tableId']?.toString() ?? map['table_id']?.toString(),
      tableNumber:
          map['tableNumber']?.toString() ?? map['table_number']?.toString(),
      deliveryDate: _tryParseDateTime(map['deliveryDate'] ?? map['delivery_date']),
      targetDeliveryTime: _tryParseDateTime(
        map['targetDeliveryTime'] ?? map['target_delivery_time'],
      ),
      prepTimeMinutes: _tryParseInt(
        map['prepTimeMinutes'] ?? map['prep_time_minutes'],
      ),
      routeTimeMinutes: _tryParseInt(
        map['routeTimeMinutes'] ?? map['route_time_minutes'],
      ),
      cashierBufferMinutes: _tryParseInt(
        map['cashierBufferMinutes'] ?? map['cashier_buffer_minutes'],
      ),
      autoReleaseTime: _tryParseDateTime(
        map['autoReleaseTime'] ?? map['auto_release_time'],
      ),
      paymentStatus:
          map['paymentStatus']?.toString() ??
          map['payment_status']?.toString(),
      paidAt: _tryParseDateTime(map['paidAt'] ?? map['paid_at']),
      heldShiftId:
          map['heldShiftId']?.toString() ?? map['held_shift_id']?.toString(),
    );
  }

  Order copyWith({
    OrderStatus? status,
    String? invoiceNumber,
    String? paymentMethod,
    List<OrderPaymentLine>? payments,
    double? subtotal,
    double? deliveryFee,
    double? totalPrice,
    String? shiftId,
    String? cashierId,
    String? cashierName,
    String? acceptedBy,
    String? acceptedByName,
    String? externalOrderId,
    double? platformCommission,
    double? customerPayableTotal,
    double? netMerchantSales,
    String? deliveryInstructions,
    bool? priceLocked,
    String? orderSource,
    String? storeName,
    String? ingestionSource,
    bool? createdFromPos,
    double? walletRedeemAmount,
    double? discountAmount,
    String? offerId,
    String? offerTitle,
    String? targetKitchenId,
    String? targetKitchenName,
    String? assignedDriverId,
    String? assignedDriverName,
    String? assignedDriverPhone,
    String? deliveryStatus,
    String? deliveryRequestId,
    double? driverFee,
    DateTime? cashierHandoffConfirmedAt,
    DateTime? driverHandoffConfirmedAt,
    double? handshakeNetToCashier,
    double? handshakeCashierPaysDriver,
    double? handshakeCollectFromCustomer,
    OrderStatusTimeline? statusTimeline,
    int? rating,
    String? reviewNote,
    bool? isRated,
    String? ratingToken,
    String? offlineTxId,
    String? tableId,
    String? tableNumber,
    DateTime? deliveryDate,
    DateTime? targetDeliveryTime,
    int? prepTimeMinutes,
    int? routeTimeMinutes,
    int? cashierBufferMinutes,
    DateTime? autoReleaseTime,
    String? paymentStatus,
    DateTime? paidAt,
    String? heldShiftId,
    List<OrderLineItem>? items,
    OrderType? orderType,
    String? customerName,
    String? phone,
    String? address,
  }) {
    return Order(
      id: id,
      customerName: customerName ?? this.customerName,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      items: items ?? this.items,
      totalPrice: totalPrice ?? this.totalPrice,
      orderType: orderType ?? this.orderType,
      status: status ?? this.status,
      createdAt: createdAt,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      payments: payments ?? this.payments,
      subtotal: subtotal ?? this.subtotal,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      governorate: governorate,
      areaName: areaName,
      deliveryZoneId: deliveryZoneId,
      addressDetails: addressDetails,
      orderSource: orderSource ?? this.orderSource,
      storeName: storeName ?? this.storeName,
      ingestionSource: ingestionSource ?? this.ingestionSource,
      createdFromPos: createdFromPos ?? this.createdFromPos,
      shiftId: shiftId ?? this.shiftId,
      cashierId: cashierId ?? this.cashierId,
      cashierName: cashierName ?? this.cashierName,
      acceptedBy: acceptedBy ?? this.acceptedBy,
      acceptedByName: acceptedByName ?? this.acceptedByName,
      externalOrderId: externalOrderId ?? this.externalOrderId,
      platformCommission: platformCommission ?? this.platformCommission,
      customerPayableTotal: customerPayableTotal ?? this.customerPayableTotal,
      netMerchantSales: netMerchantSales ?? this.netMerchantSales,
      deliveryInstructions: deliveryInstructions ?? this.deliveryInstructions,
      priceLocked: priceLocked ?? this.priceLocked,
      walletRedeemAmount: walletRedeemAmount ?? this.walletRedeemAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      offerId: offerId ?? this.offerId,
      offerTitle: offerTitle ?? this.offerTitle,
      targetKitchenId: targetKitchenId ?? this.targetKitchenId,
      targetKitchenName: targetKitchenName ?? this.targetKitchenName,
      assignedDriverId: assignedDriverId ?? this.assignedDriverId,
      assignedDriverName: assignedDriverName ?? this.assignedDriverName,
      assignedDriverPhone: assignedDriverPhone ?? this.assignedDriverPhone,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      deliveryRequestId: deliveryRequestId ?? this.deliveryRequestId,
      driverFee: driverFee ?? this.driverFee,
      cashierHandoffConfirmedAt:
          cashierHandoffConfirmedAt ?? this.cashierHandoffConfirmedAt,
      driverHandoffConfirmedAt:
          driverHandoffConfirmedAt ?? this.driverHandoffConfirmedAt,
      handshakeNetToCashier:
          handshakeNetToCashier ?? this.handshakeNetToCashier,
      handshakeCashierPaysDriver:
          handshakeCashierPaysDriver ?? this.handshakeCashierPaysDriver,
      handshakeCollectFromCustomer:
          handshakeCollectFromCustomer ?? this.handshakeCollectFromCustomer,
      statusTimeline: statusTimeline ?? this.statusTimeline,
      rating: rating ?? this.rating,
      reviewNote: reviewNote ?? this.reviewNote,
      isRated: isRated ?? this.isRated,
      ratingToken: ratingToken ?? this.ratingToken,
      offlineTxId: offlineTxId ?? this.offlineTxId,
      tableId: tableId ?? this.tableId,
      tableNumber: tableNumber ?? this.tableNumber,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      targetDeliveryTime: targetDeliveryTime ?? this.targetDeliveryTime,
      prepTimeMinutes: prepTimeMinutes ?? this.prepTimeMinutes,
      routeTimeMinutes: routeTimeMinutes ?? this.routeTimeMinutes,
      cashierBufferMinutes: cashierBufferMinutes ?? this.cashierBufferMinutes,
      autoReleaseTime: autoReleaseTime ?? this.autoReleaseTime,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paidAt: paidAt ?? this.paidAt,
      heldShiftId: heldShiftId ?? this.heldShiftId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      if ((offlineTxId ?? id).isNotEmpty) ...{
        'offline_tx_id': offlineTxId ?? id,
        'offlineTxId': offlineTxId ?? id,
      },
      'customerName': customerName,
      'phone': phone,
      'address': address,
      'items': items.map((item) => item.toMap()).toList(),
      'totalPrice': totalPrice,
      'orderType': orderType.storageValue,
      'status': status.storageValue,
      'createdAt': createdAt.toUtc().toIso8601String(),
      if (subtotal != null) 'subtotal': subtotal,
      if (deliveryFee != null) 'deliveryFee': deliveryFee,
      if (governorate != null && governorate!.isNotEmpty)
        'governorate': governorate,
      if (areaName != null && areaName!.isNotEmpty) 'areaName': areaName,
      if (deliveryZoneId != null && deliveryZoneId!.isNotEmpty)
        'deliveryZoneId': deliveryZoneId,
      if (!addressDetails.isEmpty) 'addressDetails': addressDetails.toMap(),
      if (invoiceNumber != null && invoiceNumber!.isNotEmpty)
        'invoiceNumber': invoiceNumber,
      if (paymentMethod != null && paymentMethod!.isNotEmpty)
        'paymentMethod': paymentMethod,
      if (payments != null && payments!.isNotEmpty)
        'payments': payments!.map((line) => line.toMap()).toList(),
      if (paymentStatus != null && paymentStatus!.isNotEmpty) ...{
        'paymentStatus': paymentStatus,
        'payment_status': paymentStatus,
      },
      if (paidAt != null) ...{
        'paidAt': paidAt!.toUtc().toIso8601String(),
        'paid_at': paidAt!.toUtc().toIso8601String(),
      },
      if (heldShiftId != null && heldShiftId!.isNotEmpty) ...{
        'heldShiftId': heldShiftId,
        'held_shift_id': heldShiftId,
      },
      if (orderSource != null && orderSource!.isNotEmpty)
        'orderSource': orderSource,
      if (storeName.isNotEmpty) ...{
        'storeName': storeName,
        'store_name': storeName,
      },
      if (ingestionSource.isNotEmpty) ...{
        'ingestionSource': ingestionSource,
        'ingestion_source': ingestionSource,
      },
      if (createdFromPos) ...{'createdFromPos': true, 'created_from_pos': true},
      if (shiftId != null && shiftId!.isNotEmpty) 'shiftId': shiftId,
      if (cashierId != null && cashierId!.isNotEmpty) 'cashierId': cashierId,
      if (cashierName != null && cashierName!.isNotEmpty)
        'cashierName': cashierName,
      if (acceptedBy != null && acceptedBy!.isNotEmpty)
        'acceptedBy': acceptedBy,
      if (acceptedByName != null && acceptedByName!.isNotEmpty)
        'acceptedByName': acceptedByName,
      if (externalOrderId != null && externalOrderId!.isNotEmpty)
        'externalOrderId': externalOrderId,
      if (platformCommission != null) 'platformCommission': platformCommission,
      if (customerPayableTotal != null)
        'customerPayableTotal': customerPayableTotal,
      if (netMerchantSales != null) 'netMerchantSales': netMerchantSales,
      if (deliveryInstructions.isNotEmpty)
        'deliveryInstructions': deliveryInstructions,
      if (priceLocked) 'priceLocked': true,
      if (walletRedeemAmount != null && walletRedeemAmount! > 0)
        'walletRedeemAmount': walletRedeemAmount,
      if (discountAmount != null && discountAmount! > 0)
        'discountAmount': discountAmount,
      if (offerId != null && offerId!.isNotEmpty) 'offerId': offerId,
      if (offerTitle != null && offerTitle!.isNotEmpty)
        'offerTitle': offerTitle,
      if (targetKitchenId != null && targetKitchenId!.isNotEmpty)
        'targetKitchenId': targetKitchenId,
      if (targetKitchenName != null && targetKitchenName!.isNotEmpty)
        'targetKitchenName': targetKitchenName,
      if (assignedDriverId != null && assignedDriverId!.isNotEmpty)
        'assigned_driver_id': assignedDriverId,
      if (assignedDriverName != null && assignedDriverName!.isNotEmpty)
        'assigned_driver_name': assignedDriverName,
      if (assignedDriverPhone != null && assignedDriverPhone!.isNotEmpty)
        'assigned_driver_phone': assignedDriverPhone,
      if (deliveryStatus != null && deliveryStatus!.isNotEmpty)
        'delivery_status': deliveryStatus,
      if (deliveryRequestId != null && deliveryRequestId!.isNotEmpty)
        'delivery_request_id': deliveryRequestId,
      if (driverFee != null && driverFee! > 0) 'driver_fee': driverFee,
      'status_timeline': statusTimeline.toMap(),
      if (statusTimeline.createdAt != null)
        'created_at': statusTimeline.createdAt!.toUtc().toIso8601String(),
      if (statusTimeline.acceptedAt != null)
        'accepted_at': statusTimeline.acceptedAt!.toUtc().toIso8601String(),
      if (statusTimeline.driverAssignedAt != null)
        'driver_assigned_at': statusTimeline.driverAssignedAt!
            .toUtc()
            .toIso8601String(),
      if (statusTimeline.pickedUpAt != null)
        'picked_up_at': statusTimeline.pickedUpAt!.toUtc().toIso8601String(),
      if (statusTimeline.onTheWayAt != null)
        'on_the_way_at': statusTimeline.onTheWayAt!.toUtc().toIso8601String(),
      if (statusTimeline.deliveredAt != null)
        'delivered_at': statusTimeline.deliveredAt!.toUtc().toIso8601String(),
      if (rating != null) 'rating': rating,
      if (reviewNote != null && reviewNote!.isNotEmpty)
        'reviewNote': reviewNote,
      'isRated': isRated,
      if (ratingToken != null && ratingToken!.isNotEmpty)
        'ratingToken': ratingToken,
      if (tableId != null && tableId!.isNotEmpty) 'tableId': tableId,
      if (tableNumber != null && tableNumber!.isNotEmpty)
        'tableNumber': tableNumber,
      if (deliveryDate != null)
        'deliveryDate': deliveryDate!.toUtc().toIso8601String(),
      if (targetDeliveryTime != null)
        'targetDeliveryTime': targetDeliveryTime!.toUtc().toIso8601String(),
      if (prepTimeMinutes != null) 'prepTimeMinutes': prepTimeMinutes,
      if (routeTimeMinutes != null) 'routeTimeMinutes': routeTimeMinutes,
      if (cashierBufferMinutes != null)
        'cashierBufferMinutes': cashierBufferMinutes,
      if (autoReleaseTime != null)
        'autoReleaseTime': autoReleaseTime!.toUtc().toIso8601String(),
    };
  }

  bool get isDemoOrder => id.startsWith('demo-');

  static int? _tryParseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString().trim());
  }

  static DateTime? _tryParseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is String && value.trim().isEmpty) return null;
    try {
      return _parseDateTime(value);
    } catch (_) {
      return null;
    }
  }

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
