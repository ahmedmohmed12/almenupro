import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scheduled_order.dart';
import 'orders_demo_service.dart';
import 'scheduled_release_engine.dart';

abstract class ScheduledOrdersStore {
  Future<List<ScheduledOrder>> load();
  Future<void> save(List<ScheduledOrder> orders);
}

class MemoryScheduledOrdersStore implements ScheduledOrdersStore {
  List<ScheduledOrder> saved = const [];

  @override
  Future<List<ScheduledOrder>> load() async => List<ScheduledOrder>.of(saved);

  @override
  Future<void> save(List<ScheduledOrder> orders) async {
    saved = List<ScheduledOrder>.of(orders);
  }
}

class SharedPrefsScheduledOrdersStore implements ScheduledOrdersStore {
  static const key = 'scheduled_orders_v1';

  @override
  Future<List<ScheduledOrder>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((entry) => ScheduledOrder.fromJson(Map<String, dynamic>.from(entry)))
          .where((order) => order.id.isNotEmpty)
          .toList();
    } catch (error) {
      debugPrint('scheduled orders load failed: $error');
      return const [];
    }
  }

  @override
  Future<void> save(List<ScheduledOrder> orders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode(orders.map((order) => order.toJson()).toList()),
    );
  }
}

/// Local hold clock. The admin app ticks this while it is open.
class ScheduledOrdersController extends ChangeNotifier {
  ScheduledOrdersController({ScheduledOrdersStore? store, this.interval = const Duration(seconds: 20)})
      : store = store ?? SharedPrefsScheduledOrdersStore();

  static final ScheduledOrdersController instance = ScheduledOrdersController();

  final ScheduledOrdersStore store;
  final Duration interval;
  List<ScheduledOrder> orders = const [];
  final List<ScheduledDeskAction> pendingActions = [];
  var ready = false;
  Timer? _timer;

  Future<void> start() async {
    if (_timer != null) return;
    await load();
    applyTick(DateTime.now());
    _timer = Timer.periodic(interval, (_) => applyTick(DateTime.now()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> load() async {
    orders = await store.load();
    ready = true;
    notifyListeners();
  }

  void applyTick(DateTime now) {
    final plan = planScheduledRelease(orders, now);
    final invoiceActions = dueScheduledInvoiceActions(
      OrdersDemoService.loadedOrders,
      plan.next,
      now,
    );
    if (!plan.changed && invoiceActions.isEmpty && ready) return;
    orders = plan.next;
    pendingActions.addAll(plan.actions);
    pendingActions.addAll(invoiceActions);
    ready = true;
    notifyListeners();
    unawaited(store.save(orders));
  }

  List<ScheduledDeskAction> drainActions() {
    final copy = List<ScheduledDeskAction>.of(pendingActions);
    pendingActions.clear();
    return copy;
  }

  Future<void> add(ScheduledOrder order) async {
    await upsert(order);
  }

  Future<void> upsert(ScheduledOrder order) async {
    if (!ready) await load();
    final index = orders.indexWhere((row) => row.id == order.id);
    if (index < 0) {
      orders = [...orders, order];
    } else {
      final next = List<ScheduledOrder>.of(orders);
      next[index] = order;
      orders = next;
    }
    notifyListeners();
    await store.save(orders);
  }

  Future<void> cancel(String id) async {
    orders = [
      for (final order in orders)
        if (order.id == id && order.status == ScheduledHoldStatus.scheduled)
          order.copyWith(status: ScheduledHoldStatus.cancelled)
        else
          order,
    ];
    notifyListeners();
    await store.save(orders);
  }

  Future<void> markDelivered(String id) async {
    orders = [
      for (final order in orders)
        if (order.id == id && order.status == ScheduledHoldStatus.inKitchen)
          order.copyWith(status: ScheduledHoldStatus.delivered)
        else
          order,
    ];
    notifyListeners();
    await store.save(orders);
  }

  /// Cashier can push a held order to the kitchen before the clock.
  Future<void> releaseNow(String id, DateTime now) async {
    final index = orders.indexWhere((order) => order.id == id);
    if (index < 0) return;
    final order = orders[index];
    if (order.status != ScheduledHoldStatus.scheduled) return;
    final released = order.copyWith(status: ScheduledHoldStatus.inKitchen, releasedAt: now);
    final next = List<ScheduledOrder>.of(orders);
    next[index] = released;
    orders = next;
    pendingActions.add(ScheduledDeskAction(
      kind: ScheduledDeskActionKind.kitchenRelease,
      order: released,
    ));
    notifyListeners();
    await store.save(orders);
  }
}
