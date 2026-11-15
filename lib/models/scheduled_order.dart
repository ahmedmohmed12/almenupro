import 'order.dart';

/// A held booking. It stays out of the kitchen until [releaseAt].
enum ScheduledKind { dineIn, delivery }

enum ScheduledHoldStatus { scheduled, inKitchen, delivered, cancelled }

class ScheduledOrder {
  const ScheduledOrder({
    required this.id,
    required this.kind,
    required this.customerName,
    required this.phone,
    required this.targetAt,
    required this.createdAt,
    this.tableNumber = '',
    this.partySize = 2,
    this.depositAmount = 0,
    this.preparationMinutes = 25,
    this.routeMinutes = 0,
    this.cashierBufferMinutes = 0,
    this.notes = '',
    this.status = ScheduledHoldStatus.scheduled,
    this.releasedAt,
    this.reminderSentAt,
    this.driverNotifiedAt,
  });

  final String id;
  final ScheduledKind kind;
  final String customerName;
  final String phone;
  final String tableNumber;
  final int partySize;
  final double depositAmount;
  final DateTime targetAt;
  final int preparationMinutes;
  final int routeMinutes;
  final int cashierBufferMinutes;
  final String notes;
  final ScheduledHoldStatus status;
  final DateTime createdAt;
  final DateTime? releasedAt;
  final DateTime? reminderSentAt;
  final DateTime? driverNotifiedAt;

  /// Print Release Time = target − (route + prep + cashier buffer).
  DateTime get releaseAt => targetAt.subtract(
        Duration(minutes: preparationMinutes + routeMinutes + cashierBufferMinutes),
      );

  String get orderTypeWire =>
      kind == ScheduledKind.delivery ? 'scheduled_delivery' : 'dine_in';

  DateTime get reminderAt => targetAt.subtract(const Duration(hours: 1));

  DateTime get tableLockAt => targetAt.subtract(const Duration(minutes: 30));

  DateTime get driverNoticeAt => targetAt.subtract(const Duration(minutes: 30));

  bool locksTableAt(DateTime now) {
    if (kind != ScheduledKind.dineIn || status != ScheduledHoldStatus.scheduled) {
      return false;
    }
    if (tableNumber.trim().isEmpty) return false;
    return !now.isBefore(tableLockAt) &&
        now.isBefore(targetAt.add(const Duration(hours: 2)));
  }

  ScheduledOrder copyWith({
    ScheduledHoldStatus? status,
    DateTime? targetAt,
    int? preparationMinutes,
    int? routeMinutes,
    int? cashierBufferMinutes,
    DateTime? releasedAt,
    DateTime? reminderSentAt,
    DateTime? driverNotifiedAt,
  }) {
    return ScheduledOrder(
      id: id,
      kind: kind,
      customerName: customerName,
      phone: phone,
      tableNumber: tableNumber,
      partySize: partySize,
      depositAmount: depositAmount,
      preparationMinutes: preparationMinutes ?? this.preparationMinutes,
      routeMinutes: routeMinutes ?? this.routeMinutes,
      cashierBufferMinutes: cashierBufferMinutes ?? this.cashierBufferMinutes,
      notes: notes,
      targetAt: targetAt ?? this.targetAt,
      createdAt: createdAt,
      status: status ?? this.status,
      releasedAt: releasedAt ?? this.releasedAt,
      reminderSentAt: reminderSentAt ?? this.reminderSentAt,
      driverNotifiedAt: driverNotifiedAt ?? this.driverNotifiedAt,
    );
  }

  Order toKitchenTicket() {
    final when = releasedAt ?? createdAt;
    final label = kind == ScheduledKind.dineIn
        ? 'حجز طاولة $tableNumber • $partySize أفراد'
        : 'توصيل مجدول';
    return Order(
      id: id,
      customerName: customerName,
      phone: phone,
      address: kind == ScheduledKind.dineIn ? 'طاولة $tableNumber' : notes,
      items: [
        OrderLineItem(
          menuItemId: 'scheduled',
          name: label,
          unitPrice: depositAmount,
          quantity: 1,
          selectedOptions: const [],
          specialNotes: notes,
        ),
      ],
      totalPrice: depositAmount,
      orderType: kind == ScheduledKind.dineIn ? OrderType.dineIn : OrderType.delivery,
      status: OrderStatus.confirmed,
      createdAt: when,
      invoiceNumber: id,
      tableNumber: tableNumber.isEmpty ? null : tableNumber,
      orderSource: orderTypeWire,
      deliveryInstructions: 'إطلاق مجدول',
      createdFromPos: true,
      paymentMethod: depositAmount > 0 ? 'عربون' : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'orderType': orderTypeWire,
        'status': status == ScheduledHoldStatus.inKitchen ? 'in_kitchen' : status.name,
        'customerName': customerName,
        'phone': phone,
        'tableNumber': tableNumber,
        'partySize': partySize,
        'depositAmount': depositAmount,
        'preparationMinutes': preparationMinutes,
        'routeMinutes': routeMinutes,
        'cashierBufferMinutes': cashierBufferMinutes,
        'notes': notes,
        'targetAt': targetAt.toUtc().toIso8601String(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'releasedAt': releasedAt?.toUtc().toIso8601String(),
        'reminderSentAt': reminderSentAt?.toUtc().toIso8601String(),
        'driverNotifiedAt': driverNotifiedAt?.toUtc().toIso8601String(),
      };

  factory ScheduledOrder.fromJson(Map<String, dynamic> json) {
    return ScheduledOrder(
      id: json['id']?.toString() ?? '',
      kind: json['orderType']?.toString() == 'scheduled_delivery' ||
              json['kind']?.toString() == 'delivery'
          ? ScheduledKind.delivery
          : ScheduledKind.dineIn,
      status: _statusFrom(json['status']?.toString()),
      customerName: json['customerName']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      tableNumber: json['tableNumber']?.toString() ?? '',
      partySize: (json['partySize'] as num?)?.toInt() ?? 2,
      depositAmount: (json['depositAmount'] as num?)?.toDouble() ?? 0,
      preparationMinutes: (json['preparationMinutes'] as num?)?.toInt() ?? 25,
      routeMinutes: (json['routeMinutes'] as num?)?.toInt() ?? 0,
      cashierBufferMinutes: (json['cashierBufferMinutes'] as num?)?.toInt() ?? 0,
      notes: json['notes']?.toString() ?? '',
      targetAt: DateTime.tryParse(json['targetAt']?.toString() ?? '') ?? DateTime.now(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      releasedAt: DateTime.tryParse(json['releasedAt']?.toString() ?? ''),
      reminderSentAt: DateTime.tryParse(json['reminderSentAt']?.toString() ?? ''),
      driverNotifiedAt: DateTime.tryParse(json['driverNotifiedAt']?.toString() ?? ''),
    );
  }
}

ScheduledHoldStatus _statusFrom(String? raw) {
  switch ((raw ?? '').trim()) {
    case 'in_kitchen':
    case 'inKitchen':
      return ScheduledHoldStatus.inKitchen;
    case 'delivered':
      return ScheduledHoldStatus.delivered;
    case 'cancelled':
      return ScheduledHoldStatus.cancelled;
    default:
      return ScheduledHoldStatus.scheduled;
  }
}

String scheduledStatusLabel(ScheduledHoldStatus status) {
  switch (status) {
    case ScheduledHoldStatus.scheduled:
      return 'معلق';
    case ScheduledHoldStatus.inKitchen:
      return 'في المطبخ';
    case ScheduledHoldStatus.delivered:
      return 'تم التسليم';
    case ScheduledHoldStatus.cancelled:
      return 'ملغي';
  }
}

String scheduledKindLabel(ScheduledKind kind) {
  switch (kind) {
    case ScheduledKind.dineIn:
      return 'حجز طاولة';
    case ScheduledKind.delivery:
      return 'توصيل مجدول';
  }
}
