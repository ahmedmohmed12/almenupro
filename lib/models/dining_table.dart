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
  final DateTime? updatedAt;

  bool get hasItems => cartItems.isNotEmpty;

  factory DiningTableSession.fromJson(Map<String, dynamic> json) {
    final rawCart = json['cartItems'] ?? json['cart_items'] ?? json['items'];
    final rawKitchen = json['kitchenOrderIds'] ?? json['kitchen_order_ids'];
    return DiningTableSession(
      id: json['id']?.toString() ?? '',
      openedAt: DateTime.tryParse(json['openedAt']?.toString() ?? ''),
      openedById: json['openedById']?.toString() ?? json['opened_by_id']?.toString(),
      openedByName:
          json['openedByName']?.toString() ?? json['opened_by_name']?.toString(),
      cartItems: rawCart is List
          ? rawCart
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList()
          : const [],
      notes: json['notes']?.toString() ?? '',
      customerName:
          json['customerName']?.toString() ?? json['customer_name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      kitchenOrderIds: rawKitchen is List
          ? rawKitchen.map((id) => id.toString()).toList()
          : const [],
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }
}

enum DiningTableStatus {
  available,
  occupied,
  reserved;

  static DiningTableStatus fromValue(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'occupied':
        return DiningTableStatus.occupied;
      case 'reserved':
        return DiningTableStatus.reserved;
      default:
        return DiningTableStatus.available;
    }
  }

  String get apiValue => name;

  String get labelAr {
    switch (this) {
      case DiningTableStatus.occupied:
        return 'مشغولة';
      case DiningTableStatus.reserved:
        return 'محجوزة';
      case DiningTableStatus.available:
        return 'متاحة';
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
    this.activeSession,
  });

  final String id;
  final String number;
  final String name;
  final String zone;
  final int capacity;
  final DiningTableStatus status;
  final int sortOrder;
  final DiningTableSession? activeSession;

  String get displayName => name.trim().isEmpty ? 'طاولة $number' : name.trim();

  bool get isOccupied =>
      status == DiningTableStatus.occupied || activeSession != null;

  factory DiningTable.fromJson(Map<String, dynamic> json) {
    final sessionRaw = json['activeSession'] ?? json['active_session'];
    return DiningTable(
      id: json['id']?.toString() ?? '',
      number: json['number']?.toString() ?? json['tableNumber']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      zone: json['zone']?.toString() ?? json['section']?.toString() ?? 'الصالة الرئيسية',
      capacity: (json['capacity'] as num?)?.toInt() ??
          (json['seats'] as num?)?.toInt() ??
          2,
      status: DiningTableStatus.fromValue(json['status']?.toString()),
      sortOrder: (json['sortOrder'] as num?)?.toInt() ??
          (json['sort_order'] as num?)?.toInt() ??
          0,
      activeSession: sessionRaw is Map
          ? DiningTableSession.fromJson(Map<String, dynamic>.from(sessionRaw))
          : null,
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
