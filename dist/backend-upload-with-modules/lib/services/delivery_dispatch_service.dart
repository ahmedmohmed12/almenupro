import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/delivery_dispatch.dart';
import '../utils/firebase_config.dart';
import 'api_service.dart';
import 'driver_firestore_sync.dart';

/// POS / admin live board for delivery dispatch. UI should listen, not call HTTP.
class DeliveryBoardController extends ChangeNotifier {
  DeliveryBoardController({this.restaurantId});

  static final DeliveryBoardController instance = DeliveryBoardController();

  String? restaurantId;

  var loading = false;
  String? error;
  List<DeliveryDispatchRequest> live = const [];
  List<DeliveryDispatchRequest> requests = const [];
  List<DeliveryDriver> onlineDrivers = const [];
  List<DeliveryDriver> drivers = const [];

  Timer? _timer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _driverSnapshots;
  var _busy = false;
  final Map<String, GeoPointLite> _liveLocations = {};

  void ensureStarted({String? restaurantId}) {
    if (restaurantId != null && restaurantId.trim().isNotEmpty) {
      this.restaurantId = restaurantId.trim();
    }
    if (_timer == null) start();
  }

  void start() {
    unawaited(refresh());
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(refresh());
    });
    _listenDriverLocations();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    unawaited(_driverSnapshots?.cancel() ?? Future<void>.value());
    _driverSnapshots = null;
  }

  @override
  void dispose() {
    if (identical(this, instance)) return;
    stop();
    super.dispose();
  }

  DeliveryDispatchRequest? requestForOrder(String orderId) {
    final id = orderId.trim();
    if (id.isEmpty) return null;
    for (final row in requests) {
      if ((row.orderId ?? '').trim() == id) return row;
    }
    return null;
  }

  DeliveryDriver? driverFor({
    String? driverId,
    String? driverName,
  }) {
    final id = (driverId ?? '').trim();
    if (id.isNotEmpty) {
      for (final row in drivers) {
        if (row.id == id) return _withLiveLocation(row);
      }
    }
    final name = (driverName ?? '').trim().toLowerCase();
    if (name.isNotEmpty) {
      for (final row in drivers) {
        if (row.name.trim().toLowerCase() == name) return _withLiveLocation(row);
      }
    }
    return null;
  }

  DeliveryDriver _withLiveLocation(DeliveryDriver driver) {
    final live = _liveLocations[driver.id];
    if (live == null) return driver;
    return driver.copyWith(location: live);
  }

  GeoPointLite? liveLocationFor(String? driverId) {
    final id = (driverId ?? '').trim();
    if (id.isEmpty) return null;
    return _liveLocations[id] ?? driverFor(driverId: id)?.location;
  }

  void _listenDriverLocations() {
    if (!isFirebaseConfigured) return;
    if (_driverSnapshots != null) return;
    try {
      _driverSnapshots = FirebaseFirestore.instance
          .collection('drivers')
          .snapshots()
          .listen((snapshot) {
        var changed = false;
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final point = _geoFromFirestore(
            data['last_location'] ?? data['current_location'],
          );
          if (point == null) continue;
          final previous = _liveLocations[doc.id];
          if (previous != null &&
              (previous.lat - point.lat).abs() < 0.00001 &&
              (previous.lng - point.lng).abs() < 0.00001) {
            continue;
          }
          _liveLocations[doc.id] = point;
          changed = true;
        }
        if (changed) notifyListeners();
      });
    } catch (_) {}
  }

  GeoPointLite? _geoFromFirestore(dynamic raw) {
    if (raw is GeoPoint) {
      return GeoPointLite(lat: raw.latitude, lng: raw.longitude);
    }
    if (raw is Map) {
      return GeoPointLite.tryParse(raw);
    }
    return null;
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    if (live.isEmpty && error == null) {
      loading = true;
      notifyListeners();
    }
    try {
      final results = await Future.wait([
        ApiService.instance.fetchDeliveryRequests(restaurantId: restaurantId),
        ApiService.instance.fetchDrivers(restaurantId: restaurantId),
      ]);
      requests = List<DeliveryDispatchRequest>.from(
        results[0] as List<DeliveryDispatchRequest>,
      );
      live = requests
          .where(
            (row) =>
                ['pending', 'accepted', 'picked_up', 'on_the_way', 'rejected_by_all']
                    .contains(row.status),
          )
          .take(8)
          .toList();
      drivers = List<DeliveryDriver>.from(results[1] as List<DeliveryDriver>);
      onlineDrivers = drivers.where((row) => row.isOnline).toList();
      error = null;
    } catch (err) {
      error = err.toString().replaceFirst('Exception: ', '');
    } finally {
      loading = false;
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> assign(String requestId, String driverId) async {
    await ApiService.instance.assignDeliveryDriver(
      requestId: requestId,
      driverId: driverId,
    );
    await refresh();
  }
}

/// Driver-station session: inbox, online flag, GPS pings.
class DriverSessionController extends ChangeNotifier {
  var loading = true;
  String? error;
  DeliveryDriver? driver;
  var online = false;
  List<DeliveryDispatchRequest> incoming = const [];
  List<DeliveryDispatchRequest> history = const [];
  List<MasterDeliveryRegion> regionsCatalog = const [];
  DeliveryDispatchRequest? active;
  DateTime? lastBeepAt;

  Timer? _poll;
  var _busy = false;
  String _lastSyncedFingerprint = '';

  void start() {
    unawaited(refresh());
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(refresh());
    });
  }

  void stop() {
    _poll?.cancel();
    _poll = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final payload = await ApiService.instance.fetchDriverInbox();
      final driverJson = payload['driver'];
      final incomingRaw = payload['incoming'];
      final activeRaw = payload['active'];
      final historyRaw = payload['history'];
      driver = driverJson is Map
          ? DeliveryDriver.fromJson(Map<String, dynamic>.from(driverJson))
          : null;
      incoming = incomingRaw is List
          ? incomingRaw
              .whereType<Map>()
              .map(
                (row) => DeliveryDispatchRequest.fromJson(
                  Map<String, dynamic>.from(row),
                ),
              )
              .where(
                (row) =>
                    driver == null ||
                    driver!.coversRegion(row.regionId, row.regionName),
              )
              .toList()
          : const [];
      history = historyRaw is List
          ? historyRaw
              .whereType<Map>()
              .map(
                (row) => DeliveryDispatchRequest.fromJson(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList()
          : const [];
      online = driver?.isOnline ?? online;
      unawaited(_syncAssignedRegions(driver));
      unawaited(_loadRegionsCatalog());
      active = activeRaw is Map
          ? DeliveryDispatchRequest.fromJson(Map<String, dynamic>.from(activeRaw))
          : null;
      error = null;
    } catch (err) {
      error = err.toString().replaceFirst('Exception: ', '');
    } finally {
      loading = false;
      _busy = false;
      notifyListeners();
    }
  }

  bool consumeBeep() {
    if (incoming.isEmpty) return false;
    if (lastBeepAt != null &&
        DateTime.now().difference(lastBeepAt!) < const Duration(seconds: 8)) {
      return false;
    }
    lastBeepAt = DateTime.now();
    return true;
  }

  Future<void> setOnline(bool value) async {
    final current = driver;
    if (current == null) return;
    await ApiService.instance.patchDriver(current.id, isOnline: value);
    online = value;
    notifyListeners();
    await refresh();
  }

  Future<void> _loadRegionsCatalog() async {
    if (regionsCatalog.isNotEmpty) return;
    try {
      regionsCatalog = await ApiService.instance.fetchMasterRegions();
      notifyListeners();
    } catch (_) {}
  }

  String regionLabel(String id, [String fallback = '']) {
    final key = id.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    for (final region in regionsCatalog) {
      if (region.id == key || region.id == id) return region.name;
    }
    final pretty = (fallback.isNotEmpty ? fallback : id).replaceAll('_', ' ').trim();
    return pretty.isEmpty ? 'منطقة غير محددة' : pretty;
  }

  Future<void> _syncAssignedRegions(DeliveryDriver? current) async {
    if (current == null || current.id.isEmpty) return;
    final fingerprint =
        '${current.id}|${current.activeRegionIds.join(',')}|${current.isOnline}|${current.isBusy}';
    if (fingerprint == _lastSyncedFingerprint) return;
    _lastSyncedFingerprint = fingerprint;
    await syncDriverProfileToFirestore(current);
  }

  Future<void> pushLocation(GeoPointLite? point) async {
    final current = driver;
    if (!online || current == null || point == null) return;
    try {
      await ApiService.instance.patchDriver(current.id, location: point);
    } catch (_) {}
  }

  Future<void> act(String action) async {
    final target = active ?? (incoming.isNotEmpty ? incoming.first : null);
    if (target == null) return;
    await ApiService.instance.postDeliveryAction(target.id, action);
    await refresh();
  }
}
