class DiningTableSession {
  const DiningTableSession({
    required this.id,
    this.openedAt,
    this.openedById,
    this.openedByName,
    this.cartItems = const [],
    this.notes = '',
    this.customerName = '',
    this.phone = '',
    this.kitchenOrderIds = const [],
    this.currentOrderNumber = '',
    this.checkRequested = false,
    this.checkRequestedAt,
    this.tipAmount = 0,
    this.paymentMethod = '',
    this.billTotal = 0,
    this.waiterRequested = false,
    this.waiterNote = '',
    this.waiterRequestedAt,
    this.updatedAt,
  });

  final String id;
  final DateTime? openedAt;
  final String? openedById;
  final String? openedByName;
  final List<Map<String, dynamic>> cartItems;
  final String notes;
  final String customerName;
  final String phone;
  final List<String> kitchenOrderIds;
  final String currentOrderNumber;
  final bool checkRequested;
  final DateTime? checkRequestedAt;
  final double tipAmount;
  final String paymentMethod;
  final double billTotal;
  final bool waiterRequested;
  final String waiterNote;
  final DateTime? waiterRequestedAt;
  final DateTime? updatedAt;

  bool get hasItems => cartItems.isNotEmpty;

  DiningTableSession copyWith({
    bool? checkRequested,
    DateTime? checkRequestedAt,
    double? tipAmount,
    String? paymentMethod,
    double? billTotal,
    bool? waiterRequested,
    String? waiterNote,
    DateTime? updatedAt,
  }) {
    return DiningTableSession(
      id: id,
      openedAt: openedAt,
      openedById: openedById,
      openedByName: openedByName,
      cartItems: cartItems,
      notes: notes,
      customerName: customerName,
      phone: phone,
      kitchenOrderIds: kitchenOrderIds,
      currentOrderNumber: currentOrderNumber,
      checkRequested: checkRequested ?? this.checkRequested,
      checkRequestedAt: checkRequestedAt ?? this.checkRequestedAt,
      tipAmount: tipAmount ?? this.tipAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      billTotal: billTotal ?? this.billTotal,
      waiterRequested: waiterRequested ?? this.waiterRequested,
      waiterNote: waiterNote ?? this.waiterNote,
      waiterRequestedAt: waiterRequestedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory DiningTableSession.fromJson(Map<String, dynamic> json) {
    final rawCart = json['cartItems'] ?? json['cart_items'] ?? json['items'];
    final rawKitchen = json['kitchenOrderIds'] ?? json['kitchen_order_ids'];
    return DiningTableSession(
      id: json['id']?.toString() ?? '',
      openedAt: DateTime.tryParse(json['openedAt']?.toString() ?? ''),
      openedById:
          json['openedById']?.toString() ?? json['opened_by_id']?.toString(),
      openedByName:
          json['openedByName']?.toString() ??
          json['opened_by_name']?.toString(),
      cartItems: rawCart is List
          ? rawCart
                .whereType<Map>()
                .map((entry) => Map<String, dynamic>.from(entry))
                .toList()
          : const [],
      notes: json['notes']?.toString() ?? '',
      customerName:
          json['customerName']?.toString() ??
          json['customer_name']?.toString() ??
          '',
      phone: json['phone']?.toString() ?? '',
      kitchenOrderIds: rawKitchen is List
          ? rawKitchen.map((id) => id.toString()).toList()
          : const [],
      currentOrderNumber:
          json['currentOrderNumber']?.toString() ??
          json['current_order_number']?.toString() ??
          json['lastOrderNumber']?.toString() ??
          json['last_order_number']?.toString() ??
          '',
      checkRequested:
          json['checkRequested'] == true ||
          json['check_requested'] == true ||
          json['checkRequested'] == 'true',
      checkRequestedAt: DateTime.tryParse(
        json['checkRequestedAt']?.toString() ??
            json['check_requested_at']?.toString() ??
            '',
      ),
      tipAmount:
          (json['tipAmount'] as num?)?.toDouble() ??
          (json['tip_amount'] as num?)?.toDouble() ??
          double.tryParse(
            (json['tipAmount'] ?? json['tip_amount'])?.toString() ?? '',
          ) ??
          0,
      paymentMethod:
          json['paymentMethod']?.toString() ??
          json['payment_method']?.toString() ??
          '',
      billTotal:
          (json['billTotal'] as num?)?.toDouble() ??
          (json['bill_total'] as num?)?.toDouble() ??
          double.tryParse(
            (json['billTotal'] ?? json['bill_total'])?.toString() ?? '',
          ) ??
          0,
      waiterRequested:
          json['waiterRequested'] == true || json['waiter_requested'] == true,
      waiterNote:
          json['waiterNote']?.toString() ??
          json['waiter_note']?.toString() ??
          '',
      waiterRequestedAt: DateTime.tryParse(
        json['waiterRequestedAt']?.toString() ??
            json['waiter_requested_at']?.toString() ??
            '',
      ),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }
}

enum DiningTableStatus {
  available,
  occupied,
  reserved,
  awaitingCheck,
  waiterCall;

  static DiningTableStatus fromValue(String? raw) {
    switch (raw?.trim().toLowerCase().replaceAll('-', '_')) {
      case 'occupied':
        return DiningTableStatus.occupied;
      case 'reserved':
        return DiningTableStatus.reserved;
      case 'awaiting_check':
      case 'awaitingcheck':
      case 'pending_bill':
      case 'check_requested':
        return DiningTableStatus.awaitingCheck;
      case 'waiter_call':
      case 'waitercall':
      case 'waiter_requested':
      case 'call_waiter':
        return DiningTableStatus.waiterCall;
      default:
        return DiningTableStatus.available;
    }
  }

  String get apiValue {
    switch (this) {
      case DiningTableStatus.awaitingCheck:
        return 'awaiting_check';
      case DiningTableStatus.waiterCall:
        return 'waiter_call';
      default:
        return name;
    }
  }

  String get labelAr {
    switch (this) {
      case DiningTableStatus.occupied:
        return 'مشغولة';
      case DiningTableStatus.reserved:
        return 'محجوزة';
      case DiningTableStatus.awaitingCheck:
        return 'طلب حساب';
      case DiningTableStatus.waiterCall:
        return 'طلب ويتر';
      case DiningTableStatus.available:
        return 'متاحة';
    }
  }

  String get labelEn {
    switch (this) {
      case DiningTableStatus.occupied:
        return 'Occupied';
      case DiningTableStatus.reserved:
        return 'Reserved';
      case DiningTableStatus.awaitingCheck:
        return 'Check requested';
      case DiningTableStatus.waiterCall:
        return 'Waiter requested';
      case DiningTableStatus.available:
        return 'Available';
    }
  }
}

class DiningTable {
  const DiningTable({
    required this.id,
    required this.number,
    this.name = '',
    this.zone = 'الصالة الرئيسية',
    this.capacity = 2,
    this.status = DiningTableStatus.available,
    this.sortOrder = 0,
    this.restaurantId = '',
    this.activeSession,
  });

  final String id;
  final String number;
  final String name;
  final String zone;
  final int capacity;
  final DiningTableStatus status;
  final int sortOrder;
  final String restaurantId;
  final DiningTableSession? activeSession;

  String get displayName => name.trim().isEmpty ? 'طاولة $number' : name.trim();

  bool get isOccupied => isAwaitingCheck || (activeSession?.hasItems ?? false);

  bool get isAwaitingCheck =>
      status == DiningTableStatus.awaitingCheck ||
      (activeSession?.checkRequested ?? false);

  bool get isWaiterCall =>
      !isAwaitingCheck &&
      (status == DiningTableStatus.waiterCall ||
          (activeSession?.waiterRequested ?? false));

  String get waiterNote => activeSession?.waiterNote.trim() ?? '';

  int get sessionItemCount {
    final items = activeSession?.cartItems ?? const [];
    var total = 0;
    for (final item in items) {
      total += (item['quantity'] as num?)?.toInt() ?? 1;
    }
    return total;
  }

  double get sessionAmount {
    final items = activeSession?.cartItems ?? const [];
    var total = 0.0;
    for (final item in items) {
      final quantity =
          (item['quantity'] as num?)?.toDouble() ??
          double.tryParse(item['quantity']?.toString() ?? '') ??
          1;
      final lineTotal =
          (item['lineTotal'] as num?)?.toDouble() ??
          (item['line_total'] as num?)?.toDouble() ??
          double.tryParse(
            (item['lineTotal'] ?? item['line_total'])?.toString() ?? '',
          );
      final unitPrice =
          (item['unitPrice'] as num?)?.toDouble() ??
          (item['unit_price'] as num?)?.toDouble() ??
          (item['price'] as num?)?.toDouble() ??
          double.tryParse(
            (item['unitPrice'] ?? item['unit_price'] ?? item['price'])
                    ?.toString() ??
                '',
          ) ??
          0;
      total += lineTotal ?? unitPrice * quantity;
    }
    return total;
  }

  double get requestedTip => activeSession?.tipAmount ?? 0;

  double get requestedBillTotal {
    final requested = activeSession?.billTotal ?? 0;
    return requested > 0 ? requested : sessionAmount + requestedTip;
  }

  String get requestedPaymentMethod =>
      activeSession?.paymentMethod.trim().toLowerCase() ?? '';

  String get currentOrderNumber =>
      activeSession?.currentOrderNumber.trim() ?? '';

  String get elapsedLabel => elapsedLabelFor(true);

  String elapsedLabelFor(bool isArabic) {
    final start = activeSession?.openedAt;
    if (start == null) return '';
    final minutes = DateTime.now().difference(start).inMinutes.clamp(0, 999999);
    if (minutes < 1) return isArabic ? 'الآن' : 'Now';
    if (minutes < 60) return isArabic ? '$minutes د' : '$minutes min';
    return isArabic
        ? '${minutes ~/ 60}س ${minutes % 60}د'
        : '${minutes ~/ 60}h ${minutes % 60}m';
  }

  factory DiningTable.fromJson(Map<String, dynamic> json) {
    final sessionRaw = json['activeSession'] ?? json['active_session'];
    DiningTableSession? session = sessionRaw is Map
        ? DiningTableSession.fromJson(Map<String, dynamic>.from(sessionRaw))
        : null;
    if (session == null &&
        (json['waiterRequested'] == true || json['checkRequested'] == true)) {
      session = DiningTableSession(
        id: 'public',
        waiterRequested: json['waiterRequested'] == true,
        waiterNote: json['waiterNote']?.toString() ?? '',
        checkRequested: json['checkRequested'] == true,
      );
    }
    return DiningTable(
      id: json['id']?.toString() ?? '',
      number:
          json['number']?.toString() ?? json['tableNumber']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      zone:
          json['zone']?.toString() ??
          json['section']?.toString() ??
          'الصالة الرئيسية',
      capacity:
          (json['capacity'] as num?)?.toInt() ??
          (json['seats'] as num?)?.toInt() ??
          2,
      status: DiningTableStatus.fromValue(json['status']?.toString()),
      sortOrder:
          (json['sortOrder'] as num?)?.toInt() ??
          (json['sort_order'] as num?)?.toInt() ??
          0,
      restaurantId:
          json['restaurantId']?.toString() ??
          json['restaurant_id']?.toString() ??
          '',
      activeSession: session,
    );
  }

  DiningTable copyWith({
    DiningTableStatus? status,
    DiningTableSession? activeSession,
    bool clearSession = false,
  }) {
    return DiningTable(
      id: id,
      number: number,
      name: name,
      zone: zone,
      capacity: capacity,
      status: status ?? this.status,
      sortOrder: sortOrder,
      restaurantId: restaurantId,
      activeSession: clearSession
          ? null
          : (activeSession ?? this.activeSession),
    );
  }

  Map<String, dynamic> toPayload() => {
    'number': number,
    'name': name,
    'zone': zone,
    'capacity': capacity,
    'status': status.apiValue,
    'sortOrder': sortOrder,
  };
}
