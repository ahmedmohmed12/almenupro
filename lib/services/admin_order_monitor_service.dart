import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/order.dart';
import 'order_alert_sound_service.dart';
import 'order_browser_notification_service.dart';
import 'orders_demo_service.dart';
import 'orders_service.dart';

typedef AdminNewOrderHandler = void Function(Order order);

/// Background order watcher for the admin dashboard (all sidebar tabs).
class AdminOrderMonitorService {
  AdminOrderMonitorService._();

  static final AdminOrderMonitorService instance = AdminOrderMonitorService._();

  static const _pollInterval = Duration(seconds: 5);

  final ValueNotifier<int> pendingCount = ValueNotifier(0);
  final ValueNotifier<bool> alertLoopActive = ValueNotifier(false);

  StreamSubscription<List<Order>>? _ordersSubscription;
  Timer? _pollTimer;
  final Set<String> _knownOrderIds = <String>{};
  var _initializedSnapshot = false;
  var _isRunning = false;
  AdminNewOrderHandler? onNewPendingOrder;

  bool get isRunning => _isRunning;

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    await OrderAlertSoundService.instance.initialize();

    _ordersSubscription = OrdersService.instance.watchOrders().listen(
      _handleOrders,
      onError: (Object error, StackTrace stackTrace) {
        if (kDebugMode) {
          debugPrint('Admin order monitor stream error: $error');
        }
      },
    );

    _pollTimer ??= Timer.periodic(_pollInterval, (_) {
      unawaited(OrdersService.instance.refreshOrders());
    });

    unawaited(OrdersService.instance.refreshOrders());
  }

  Future<void> stop() async {
    _isRunning = false;
    await _ordersSubscription?.cancel();
    _ordersSubscription = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _initializedSnapshot = false;
    _knownOrderIds.clear();
    await OrderAlertSoundService.instance.stopAllAlerts();
    _syncAlertLoopFlag();
    pendingCount.value = 0;
  }

  Future<void> acknowledgeOrder(String orderId) =>
      OrderAlertSoundService.instance.acknowledgeOrder(orderId);

  Future<void> stopAllAlerts() async {
    await OrderAlertSoundService.instance.stopAllAlerts();
    _syncAlertLoopFlag();
  }

  Future<void> _handleOrders(List<Order> orders) async {
    final pendingOrders =
        orders.where((order) => order.status == OrderStatus.pending).toList();
    final pendingIds = pendingOrders.map((order) => order.id).toSet();

    pendingCount.value = pendingOrders.length;

    if (!_initializedSnapshot) {
      _knownOrderIds
        ..clear()
        ..addAll(orders.map((order) => order.id));
      _initializedSnapshot = true;
      await OrderAlertSoundService.instance.syncPendingAlerts(pendingIds);
      _syncAlertLoopFlag();
      return;
    }

    final newlyDetected = <String>{};

    for (final order in pendingOrders) {
      if (_knownOrderIds.contains(order.id)) continue;
      newlyDetected.add(order.id);
      _knownOrderIds.add(order.id);
      onNewPendingOrder?.call(order);
      await OrderBrowserNotificationService.instance.notifyNewOrder(order);
    }

    await OrderAlertSoundService.instance.syncPendingAlerts(
      pendingIds,
      newlyDetected: newlyDetected,
    );
    _syncAlertLoopFlag();

    _knownOrderIds
      ..clear()
      ..addAll(orders.map((order) => order.id));
  }

  void _syncAlertLoopFlag() {
    alertLoopActive.value =
        OrderAlertSoundService.instance.isAlertLoopActive;
  }
}
