import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/manager_report_snapshot.dart';
import '../models/manager_report_period.dart';
import '../models/order.dart';
import '../models/shift_session.dart';
import '../utils/firebase_config.dart';
import 'api_service.dart';
import 'firebase_service.dart';
import 'orders_service.dart';
import 'pos_operations_service.dart';

/// Live manager KPIs from Firestore `onSnapshot` plus API-scoped order/shift feeds.
class ManagerLiveReportService extends ChangeNotifier {
  ManagerLiveReportService();

  final _firebase = FirebaseService();
  StreamSubscription<List<Order>>? _firebaseSub;
  StreamSubscription<List<Order>>? _apiSub;
  Timer? _shiftTimer;
  Timer? _historyTimer;

  String _restaurantId = '';
  List<Order> _firebaseOrders = const [];
  List<Order> _apiOrders = const [];
  List<Order> _historyOrders = const [];
  List<ShiftSession> _shifts = const [];
  List<Order> _prevMerged = const [];
  List<ShiftSession> _prevShifts = const [];
  var _alerts = <ManagerAlert>[];
  var period = ManagerReportPeriod.live;

  ManagerReportSnapshot snapshot = ManagerReportSnapshot.empty();
  var listening = false;

  void start(String restaurantId) {
    if (listening && restaurantId == _restaurantId) return;
    stop();
    _restaurantId = restaurantId;
    listening = true;
    _firebaseOrders = const [];
    _historyOrders = const [];
    _apiOrders = const [];

    _apiSub = OrdersService.instance.watchOrders().listen((orders) {
      _apiOrders = orders;
      _rebuild(liveFromFirebase: false);
    });

    if (isFirebaseConfigured && _firebase.isAvailable) {
      _firebaseSub = _firebase
          .watchOrders(restaurantId: restaurantId)
          .listen((orders) {
        _firebaseOrders = orders;
        _rebuild(liveFromFirebase: true);
      }, onError: (Object error) {
        if (kDebugMode) {
          debugPrint('Manager Firestore watch failed: $error');
        }
      });
    }

    unawaited(OrdersService.instance.refreshOrders());
    unawaited(_refreshHistory());
    unawaited(_refreshShifts());
    _shiftTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(_refreshShifts());
      unawaited(OrdersService.instance.refreshOrders());
    });
    _historyTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_refreshHistory());
    });
  }

  void setPeriod(ManagerReportPeriod next) {
    if (period == next) return;
    period = next;
    _rebuild(liveFromFirebase: snapshot.live);
  }

  Future<void> _refreshHistory() async {
    if (_restaurantId.isEmpty) return;
    try {
      _historyOrders = await ApiService.instance.fetchOrders(
        from: DateTime.now().toUtc().subtract(const Duration(days: 31)),
      );
      _rebuild(liveFromFirebase: snapshot.live);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Manager history fetch failed: $error');
      }
    }
  }

  Future<void> _refreshShifts() async {
    if (_restaurantId.isEmpty) return;
    try {
      final result = await PosOperationsService.instance.fetchShiftReports(
        restaurantId: _restaurantId,
        from: DateTime.now().toUtc().subtract(const Duration(days: 31)),
        includeOpen: true,
      );
      _shifts = result.shifts;
      _rebuild(liveFromFirebase: snapshot.live);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Manager shift poll failed: $error');
      }
    }
  }

  void _rebuild({required bool liveFromFirebase}) {
    final merged = _mergeOrders(_apiOrders, _firebaseOrders);
    final freshAlerts = detectManagerAlerts(
      previous: _prevMerged,
      next: merged,
      previousShifts: _prevShifts,
      nextShifts: _shifts,
    );
    if (freshAlerts.isNotEmpty) {
      _alerts = [...freshAlerts, ..._alerts].take(8).toList();
    }
    _prevMerged = merged;
    _prevShifts = _shifts;
    snapshot = buildManagerReport(
      orders: merged,
      shifts: _shifts,
      now: DateTime.now(),
      alerts: period.isLive || period == ManagerReportPeriod.today
          ? _alerts
          : const [],
      live: liveFromFirebase || isFirebaseConfigured,
      period: period,
    );
    notifyListeners();
  }

  List<Order> _mergeOrders(List<Order> api, List<Order> firebase) {
    final byId = <String, Order>{};
    for (final order in _historyOrders) {
      if (order.id.trim().isEmpty) continue;
      byId[order.id] = order;
    }
    for (final order in firebase) {
      if (order.id.trim().isEmpty) continue;
      byId[order.id] = order;
    }
    for (final order in api) {
      if (order.id.trim().isEmpty) continue;
      byId[order.id] = order;
    }
    return byId.values.toList();
  }

  void dismissAlert(String id) {
    _alerts = _alerts.where((a) => a.id != id).toList();
    snapshot = buildManagerReport(
      orders: _mergeOrders(_apiOrders, _firebaseOrders),
      shifts: _shifts,
      now: DateTime.now(),
      alerts: period.isLive || period == ManagerReportPeriod.today
          ? _alerts
          : const [],
      live: snapshot.live,
      period: period,
    );
    notifyListeners();
  }

  void stop() {
    listening = false;
    _firebaseSub?.cancel();
    _apiSub?.cancel();
    _shiftTimer?.cancel();
    _historyTimer?.cancel();
    _firebaseSub = null;
    _apiSub = null;
    _shiftTimer = null;
    _historyTimer = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
