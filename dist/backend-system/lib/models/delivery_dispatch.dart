import 'dart:math' as math;

class GeoPointLite {
  const GeoPointLite({required this.lat, required this.lng});

  final double lat;
  final double lng;

  static GeoPointLite? tryParse(Object? raw) {
    if (raw is GeoPointLite) return raw;
    if (raw is! Map) return null;
    final lat = double.tryParse('${raw['lat'] ?? raw['latitude'] ?? ''}');
    final lng = double.tryParse('${raw['lng'] ?? raw['longitude'] ?? ''}');
    if (lat == null || lng == null) return null;
    return GeoPointLite(lat: lat, lng: lng);
  }

  Map<String, double> toMap() => {'lat': lat, 'lng': lng};

  double? distanceKmTo(GeoPointLite other) {
    const earthKm = 6371.0;
    final dLat = _toRad(other.lat - lat);
    final dLng = _toRad(other.lng - lng);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat)) *
            math.cos(_toRad(other.lat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * earthKm * math.asin(math.sqrt(a.clamp(0, 1)));
  }

  int? etaMinutesTo(GeoPointLite other, {double kmPerHour = 25}) {
    final km = distanceKmTo(other);
    if (km == null || kmPerHour <= 0) return null;
    final minutes = (km / kmPerHour * 60).round();
    return minutes < 1 ? 1 : minutes;
  }

  static double _toRad(double deg) => deg * math.pi / 180;
}

class MasterDeliveryRegion {
  const MasterDeliveryRegion({
    required this.id,
    required this.name,
    this.governorate = '',
  });

  final String id;
  final String name;
  final String governorate;

  factory MasterDeliveryRegion.fromJson(Map<String, dynamic> json) {
    return MasterDeliveryRegion(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      governorate: json['governorate']?.toString() ?? '',
    );
  }
}

class DeliveryDriver {
  const DeliveryDriver({
    required this.id,
    required this.name,
    this.phone = '',
    this.civilId = '',
    this.civilIdPhotoUrl = '',
    this.licensePhotoUrl = '',
    this.isOnline = false,
    this.isBusy = false,
    this.location,
    this.lastUpdated,
    this.availableSince,
    this.suspendedUntil,
    this.staffId,
    this.allowedDeliveryRegions = const [],
    this.assignedRegions = const {},
  });

  final String id;
  final String name;
  final String phone;
  final String civilId;
  final String civilIdPhotoUrl;
  final String licensePhotoUrl;
  final bool isOnline;
  final bool isBusy;
  final GeoPointLite? location;
  final DateTime? lastUpdated;
  final DateTime? availableSince;
  final DateTime? suspendedUntil;
  final String? staffId;
  final List<String> allowedDeliveryRegions;
  final Map<String, bool> assignedRegions;

  factory DeliveryDriver.fromJson(Map<String, dynamic> json) {
    final regions = json['allowed_delivery_regions'] ?? json['allowedDeliveryRegions'];
    final assignedRaw = json['assigned_regions'] ?? json['assignedRegions'];
    final assigned = <String, bool>{};
    if (assignedRaw is Map) {
      assignedRaw.forEach((key, value) {
        final id = key.toString().trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
        if (id.isEmpty) return;
        assigned[id] = value == true;
      });
    }
    final allowed = regions is List
        ? regions.map((entry) => entry.toString()).where((entry) => entry.isNotEmpty).toList()
        : assigned.entries.where((e) => e.value).map((e) => e.key).toList();
    return DeliveryDriver(
      id: json['id']?.toString() ?? json['driver_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      civilId: json['civil_id']?.toString() ?? json['civilId']?.toString() ?? '',
      civilIdPhotoUrl:
          json['civil_id_photo_url']?.toString() ?? json['civilIdPhotoUrl']?.toString() ?? '',
      licensePhotoUrl:
          json['license_photo_url']?.toString() ?? json['licensePhotoUrl']?.toString() ?? '',
      isOnline: json['is_online'] == true || json['isOnline'] == true,
      isBusy: json['is_busy'] == true || json['isBusy'] == true,
      location: GeoPointLite.tryParse(
        json['last_location'] ??
            json['lastLocation'] ??
            json['current_location'] ??
            json['currentLocation'],
      ),
      lastUpdated: DateTime.tryParse(
        json['last_updated']?.toString() ?? json['lastUpdated']?.toString() ?? '',
      ),
      availableSince: DateTime.tryParse(
        json['available_since']?.toString() ?? json['availableSince']?.toString() ?? '',
      ),
      suspendedUntil: DateTime.tryParse(
        json['suspended_until']?.toString() ?? json['suspendedUntil']?.toString() ?? '',
      ),
      staffId: json['staff_id']?.toString() ?? json['staffId']?.toString(),
      allowedDeliveryRegions: allowed,
      assignedRegions: assigned,
    );
  }

  DeliveryDriver copyWith({
    Map<String, bool>? assignedRegions,
    List<String>? allowedDeliveryRegions,
    GeoPointLite? location,
    bool? isOnline,
    bool? isBusy,
    DateTime? lastUpdated,
    DateTime? availableSince,
    DateTime? suspendedUntil,
  }) {
    return DeliveryDriver(
      id: id,
      name: name,
      phone: phone,
      civilId: civilId,
      civilIdPhotoUrl: civilIdPhotoUrl,
      licensePhotoUrl: licensePhotoUrl,
      isOnline: isOnline ?? this.isOnline,
      isBusy: isBusy ?? this.isBusy,
      location: location ?? this.location,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      availableSince: availableSince ?? this.availableSince,
      suspendedUntil: suspendedUntil ?? this.suspendedUntil,
      staffId: staffId,
      allowedDeliveryRegions: allowedDeliveryRegions ?? this.allowedDeliveryRegions,
      assignedRegions: assignedRegions ?? this.assignedRegions,
    );
  }

  List<String> get activeRegionIds => assignedRegions.entries
      .where((entry) => entry.value)
      .map((entry) => entry.key)
      .toList();

  static String regionKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
  }

  bool coversRegion(String regionId, String regionName) {
    final aliases = <String>{
      regionKey(regionId),
      regionKey(regionName),
      ...regionKey(regionId).split(RegExp(r'[_\-/]')).where((part) => part.length > 1),
    }..removeWhere((entry) => entry.isEmpty);
    if (aliases.isEmpty) return false;
    final map = assignedRegions;
    if (map.isNotEmpty) {
      return map.entries.any((entry) {
        if (entry.value != true) return false;
        final key = regionKey(entry.key);
        return aliases.contains(key) ||
            aliases.any((alias) => alias.contains(key) || key.contains(alias));
      });
    }
    return allowedDeliveryRegions.any((entry) {
      final key = regionKey(entry);
      return aliases.contains(key) ||
          aliases.any((alias) => alias.contains(key) || key.contains(alias));
    });
  }
}

class DeliveryDispatchRequest {
  const DeliveryDispatchRequest({
    required this.id,
    this.orderId,
    this.isExpress = false,
    this.customerFee = 0,
    this.driverFee = 0,
    this.cashToCollect = 0,
    this.status = 'pending',
    this.assignedDriverId,
    this.assignedDriverName,
    this.assignedDriverPhone,
    this.regionId = '',
    this.regionName = '',
    this.customerPhone = '',
    this.customerAddress = '',
    this.restaurantName = '',
    this.restaurantLocation,
    this.customerLocation,
    this.offerExpiresAt,
    this.acceptedAt,
    this.pickedUpAt,
    this.onTheWayAt,
    this.deliveredAt,
    this.adminDelivered = false,
    this.adminDeliveredAt,
    this.adminDeliveredBy,
    this.createdAt,
    this.updatedAt,
    this.searchRadiusKm = 5,
    this.delayed = false,
    this.etaMinutes,
    this.paymentMethod = '',
    this.handshakePaymentKind,
    this.handshakeOrderTotal,
    this.handshakeDriverFee,
    this.handshakeNetToCashier,
    this.handshakeCashierPaysDriver,
    this.handshakeCollectFromCustomer,
    this.cashierHandoffConfirmedAt,
    this.driverHandoffConfirmedAt,
  });

  final String id;
  final String? orderId;
  final bool isExpress;
  final double customerFee;
  final double driverFee;
  final double cashToCollect;
  final String status;
  final String? assignedDriverId;
  final String? assignedDriverName;
  final String? assignedDriverPhone;
  final String regionId;
  final String regionName;
  final String customerPhone;
  final String customerAddress;
  final String restaurantName;
  final GeoPointLite? restaurantLocation;
  final GeoPointLite? customerLocation;
  final DateTime? offerExpiresAt;
  final DateTime? acceptedAt;
  final DateTime? pickedUpAt;
  final DateTime? onTheWayAt;
  final DateTime? deliveredAt;
  final bool adminDelivered;
  final DateTime? adminDeliveredAt;
  final String? adminDeliveredBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final double searchRadiusKm;
  final bool delayed;
  final int? etaMinutes;
  final String paymentMethod;
  final String? handshakePaymentKind;
  final double? handshakeOrderTotal;
  final double? handshakeDriverFee;
  final double? handshakeNetToCashier;
  final double? handshakeCashierPaysDriver;
  final double? handshakeCollectFromCustomer;
  final DateTime? cashierHandoffConfirmedAt;
  final DateTime? driverHandoffConfirmedAt;

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isPickedUp => status == 'picked_up';
  bool get isOnTheWay => status == 'on_the_way';
  bool get isRejectedByAll => status == 'rejected_by_all';

  String get statusLabelAr {
    switch (status) {
      case 'accepted':
        return assignedDriverName == null || assignedDriverName!.isEmpty
            ? 'تم القبول'
            : 'قبله ${assignedDriverName!}';
      case 'picked_up':
        return 'تم الاستلام';
      case 'on_the_way':
        return 'في الطريق للعميل';
      case 'delivered':
        return 'تم التوصيل';
      case 'rejected_by_all':
        return 'لا يوجد سائق';
      case 'cancelled':
        return 'ملغى';
      default:
        return 'جاري البحث عن سائق';
    }
  }

  factory DeliveryDispatchRequest.fromJson(Map<String, dynamic> json) {
    double numOf(Object? value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return DeliveryDispatchRequest(
      id: json['id']?.toString() ?? json['request_id']?.toString() ?? '',
      orderId: json['order_id']?.toString() ?? json['orderId']?.toString(),
      isExpress: json['is_express'] == true || json['isExpress'] == true,
      customerFee: numOf(json['customer_fee'] ?? json['customerFee']),
      driverFee: numOf(json['driver_fee'] ?? json['driverFee']),
      cashToCollect: numOf(json['cash_to_collect'] ?? json['cashToCollect']),
      status: json['status']?.toString() ?? 'pending',
      assignedDriverId:
          json['assigned_driver_id']?.toString() ?? json['assignedDriverId']?.toString(),
      assignedDriverName:
          json['assigned_driver_name']?.toString() ?? json['assignedDriverName']?.toString(),
      assignedDriverPhone:
          json['assigned_driver_phone']?.toString() ?? json['assignedDriverPhone']?.toString(),
      regionId: json['destination_region_id']?.toString() ??
          json['region_id']?.toString() ??
          json['regionId']?.toString() ??
          '',
      regionName: json['region_name']?.toString() ?? json['regionName']?.toString() ?? '',
      customerPhone:
          json['customer_phone']?.toString() ?? json['customerPhone']?.toString() ?? '',
      customerAddress:
          json['customer_address']?.toString() ?? json['customerAddress']?.toString() ?? '',
      restaurantName: json['restaurantName']?.toString() ??
          json['restaurant_name']?.toString() ??
          '',
      restaurantLocation:
          GeoPointLite.tryParse(json['restaurant_location'] ?? json['restaurantLocation']),
      customerLocation:
          GeoPointLite.tryParse(json['customer_location'] ?? json['customerLocation']),
      offerExpiresAt: DateTime.tryParse(
        json['offer_expires_at']?.toString() ?? json['offerExpiresAt']?.toString() ?? '',
      ),
      acceptedAt: DateTime.tryParse(
        json['accepted_at']?.toString() ?? json['acceptedAt']?.toString() ?? '',
      ),
      pickedUpAt: DateTime.tryParse(
        json['picked_up_at']?.toString() ?? json['pickedUpAt']?.toString() ?? '',
      ),
      onTheWayAt: DateTime.tryParse(
        json['on_the_way_at']?.toString() ?? json['onTheWayAt']?.toString() ?? '',
      ),
      deliveredAt: DateTime.tryParse(
        json['delivered_at']?.toString() ?? json['deliveredAt']?.toString() ?? '',
      ),
      adminDelivered: json['admin_delivered'] == true || json['adminDelivered'] == true,
      adminDeliveredAt: DateTime.tryParse(
        json['admin_delivered_at']?.toString() ?? json['adminDeliveredAt']?.toString() ?? '',
      ),
      adminDeliveredBy:
          json['admin_delivered_by']?.toString() ?? json['adminDeliveredBy']?.toString(),
      createdAt: DateTime.tryParse(
        json['created_at']?.toString() ?? json['createdAt']?.toString() ?? '',
      ),
      updatedAt: DateTime.tryParse(
        json['updated_at']?.toString() ?? json['updatedAt']?.toString() ?? '',
      ),
      searchRadiusKm: numOf(json['search_radius_km'] ?? json['searchRadiusKm']).clamp(1, 50).toDouble(),
      delayed: json['delayed'] == true,
      etaMinutes: int.tryParse('${json['eta_minutes'] ?? json['etaMinutes'] ?? ''}'),
      paymentMethod: json['payment_method']?.toString() ?? json['paymentMethod']?.toString() ?? '',
      handshakePaymentKind: json['handshake_payment_kind']?.toString() ??
          json['handshakePaymentKind']?.toString(),
      handshakeOrderTotal: json['handshake_order_total'] == null
          ? null
          : numOf(json['handshake_order_total'] ?? json['handshakeOrderTotal']),
      handshakeDriverFee: json['handshake_driver_fee'] == null
          ? null
          : numOf(json['handshake_driver_fee'] ?? json['handshakeDriverFee']),
      handshakeNetToCashier: json['handshake_net_to_cashier'] == null
          ? null
          : numOf(json['handshake_net_to_cashier'] ?? json['handshakeNetToCashier']),
      handshakeCashierPaysDriver: json['handshake_cashier_pays_driver'] == null
          ? null
          : numOf(json['handshake_cashier_pays_driver'] ?? json['handshakeCashierPaysDriver']),
      handshakeCollectFromCustomer: json['handshake_collect_from_customer'] == null
          ? null
          : numOf(json['handshake_collect_from_customer'] ?? json['handshakeCollectFromCustomer']),
      cashierHandoffConfirmedAt: DateTime.tryParse(
        json['cashier_handoff_confirmed_at']?.toString() ??
            json['cashierHandoffConfirmedAt']?.toString() ??
            '',
      ),
      driverHandoffConfirmedAt: DateTime.tryParse(
        json['driver_handoff_confirmed_at']?.toString() ??
            json['driverHandoffConfirmedAt']?.toString() ??
            '',
      ),
    );
  }
}

class FleetOpsSummary {
  const FleetOpsSummary({
    this.available = 0,
    this.pickingUp = 0,
    this.delivering = 0,
    this.delayed = 0,
    this.needsDriver = 0,
  });

  final int available;
  final int pickingUp;
  final int delivering;
  final int delayed;
  final int needsDriver;

  factory FleetOpsSummary.fromJson(Map<String, dynamic> json) {
    int n(Object? value) => int.tryParse(value?.toString() ?? '') ?? 0;
    return FleetOpsSummary(
      available: n(json['available']),
      pickingUp: n(json['picking_up'] ?? json['pickingUp']),
      delivering: n(json['delivering']),
      delayed: n(json['delayed']),
      needsDriver: n(json['needs_driver'] ?? json['needsDriver']),
    );
  }
}

class DriverLedgerEntry {
  const DriverLedgerEntry({
    required this.id,
    this.orderId = '',
    this.invoiceNumber = '',
    this.createdAt,
    this.restaurantName = '',
    this.cashierId = '',
    this.cashierName = '',
    this.paymentKind = '',
    this.netToCashier = 0,
    this.driverFee = 0,
    this.dualStatus = '',
  });

  final String id;
  final String orderId;
  final String invoiceNumber;
  final DateTime? createdAt;
  final String restaurantName;
  final String cashierId;
  final String cashierName;
  final String paymentKind;
  final double netToCashier;
  final double driverFee;
  final String dualStatus;

  factory DriverLedgerEntry.fromJson(Map<String, dynamic> json) {
    double n(Object? value) => double.tryParse(value?.toString() ?? '') ?? 0;
    return DriverLedgerEntry(
      id: json['id']?.toString() ?? '',
      orderId: json['order_id']?.toString() ?? json['orderId']?.toString() ?? '',
      invoiceNumber: json['invoice_number']?.toString() ?? json['invoiceNumber']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? json['createdAt']?.toString() ?? ''),
      restaurantName: json['restaurant_name']?.toString() ?? json['restaurantName']?.toString() ?? '',
      cashierId: json['cashier_id']?.toString() ?? json['cashierId']?.toString() ?? '',
      cashierName: json['cashier_name']?.toString() ?? json['cashierName']?.toString() ?? '',
      paymentKind: json['payment_kind']?.toString() ?? json['paymentKind']?.toString() ?? '',
      netToCashier: n(json['net_to_cashier'] ?? json['netToCashier']),
      driverFee: n(json['driver_fee'] ?? json['driverFee']),
      dualStatus: json['dual_status']?.toString() ?? json['dualStatus']?.toString() ?? '',
    );
  }
}

class FleetOpsDriver {
  const FleetOpsDriver({
    required this.driver,
    this.opsStatus = 'offline',
    this.delayed = false,
    this.idleMinutes = 0,
    this.activeOrders = const [],
  });

  final DeliveryDriver driver;
  final String opsStatus;
  final bool delayed;
  final int idleMinutes;
  final List<DeliveryDispatchRequest> activeOrders;

  String get id => driver.id;

  factory FleetOpsDriver.fromJson(Map<String, dynamic> json) {
    final ordersRaw = json['active_orders'] ?? json['activeOrders'];
    return FleetOpsDriver(
      driver: DeliveryDriver.fromJson(json),
      opsStatus: json['ops_status']?.toString() ?? json['opsStatus']?.toString() ?? 'offline',
      delayed: json['delayed'] == true,
      idleMinutes: int.tryParse('${json['idle_minutes'] ?? json['idleMinutes'] ?? 0}') ?? 0,
      activeOrders: ordersRaw is List
          ? ordersRaw
              .whereType<Map>()
              .map((row) => DeliveryDispatchRequest.fromJson(Map<String, dynamic>.from(row)))
              .toList()
          : const [],
    );
  }
}

class FleetOpsSnapshot {
  const FleetOpsSnapshot({
    this.summary = const FleetOpsSummary(),
    this.drivers = const [],
    this.needsDriver = const [],
  });

  final FleetOpsSummary summary;
  final List<FleetOpsDriver> drivers;
  final List<DeliveryDispatchRequest> needsDriver;

  factory FleetOpsSnapshot.fromJson(Map<String, dynamic> json) {
    final summaryRaw = json['summary'];
    final driversRaw = json['drivers'];
    final needsRaw = json['needs_driver'] ?? json['needsDriver'];
    return FleetOpsSnapshot(
      summary: summaryRaw is Map
          ? FleetOpsSummary.fromJson(Map<String, dynamic>.from(summaryRaw))
          : const FleetOpsSummary(),
      drivers: driversRaw is List
          ? driversRaw
              .whereType<Map>()
              .map((row) => FleetOpsDriver.fromJson(Map<String, dynamic>.from(row)))
              .toList()
          : const [],
      needsDriver: needsRaw is List
          ? needsRaw
              .whereType<Map>()
              .map((row) => DeliveryDispatchRequest.fromJson(Map<String, dynamic>.from(row)))
              .toList()
          : const [],
    );
  }
}
