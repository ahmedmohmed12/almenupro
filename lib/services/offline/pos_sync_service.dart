import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/cart_item.dart';
import '../../models/menu_item.dart';
import '../../models/order.dart';
import '../../models/shift_session.dart';
import '../api_service.dart';
import '../admin_auth_service.dart';
import '../dining_tables_service.dart';
import '../orders_demo_service.dart';
import '../firebase_service.dart';
import '../../utils/firebase_config.dart';
import 'pos_connectivity.dart';
import 'pos_local_drafts.dart';
import 'pos_offline_db.dart';

enum PosSyncTone { green, amber, red }

class PosSyncService extends ChangeNotifier {
  PosSyncService._();

  static final PosSyncService instance = PosSyncService._();

  final _browser = createPosBrowserLink();
  Timer? _pollTimer;
  var _started = false;
  var _online = true;
  var _syncing = false;
  var _pendingCount = 0;
  DateTime? _lastCatalogRefresh;

  bool get isOnline => _online;
  bool get isSyncing => _syncing;
  int get pendingCount => _pendingCount;

  PosSyncTone get tone {
    if (!_online) return PosSyncTone.red;
    if (_pendingCount > 0 || _syncing) return PosSyncTone.amber;
    return PosSyncTone.green;
  }

  String get statusLabelAr {
    return switch (tone) {
      PosSyncTone.green => 'متصل - بيانات متزامنة',
      PosSyncTone.amber =>
        'عمل محلي - جاري المزامنة ($_pendingCount طلبات معلقة)',
      PosSyncTone.red => 'انقطاع الاتصال - تم التخزين محلياً',
    };
  }

  Future<void> start() async {
    if (_started) {
      await refreshPendingCount();
      return;
    }
    _started = true;
    _online = _browser.navigatorOnline && _browser.websocketOnline;
    _browser.attach(_onBrowserOnline);
    _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      unawaited(_probeAndFlush());
    });
    await refreshPendingCount();
    unawaited(_probeAndFlush());
  }

  void _onBrowserOnline(bool online) {
    _online = online && _browser.websocketOnline;
    notifyListeners();
    if (_online) unawaited(flushQueue());
  }

  Future<void> _probeAndFlush() async {
    final reachable = await ApiService.instance.isOnline();
    final nextOnline =
        reachable && _browser.navigatorOnline && _browser.websocketOnline;
    if (nextOnline != _online) {
      _online = nextOnline;
      notifyListeners();
    }
    if (_online) await flushQueue();
  }

  Future<void> refreshPendingCount() async {
    try {
      final pending = await posOfflineStore.listQueuePending();
      final drafts = await PosLocalDrafts.listPendingOrders();
      final ids = <String>{
        ...pending.map((row) => row['id']?.toString() ?? ''),
        ...drafts.map((row) => row['id']?.toString() ?? ''),
      }..removeWhere((id) => id.isEmpty);
      _pendingCount = ids.length;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> cacheCatalog(String restaurantId, List<MenuItem> items) async {
    try {
      await posOfflineStore.putCatalog(
        restaurantId,
        items.map((item) => item.toJson()).toList(),
      );
    } catch (error) {
      debugPrint('POS catalog cache skipped: $error');
    }
  }

  Future<List<MenuItem>> loadCachedCatalog(String restaurantId) async {
    try {
      final rows = await posOfflineStore.getCatalog(restaurantId);
      return rows.map((row) {
        final json = Map<String, dynamic>.from(row);
        json['id'] = json['itemId'] ?? json['id']?.toString().split(':').last;
        return MenuItem.fromJson(json);
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveActiveOrder({
    required String id,
    required String restaurantId,
    required List<Map<String, dynamic>> cartItems,
    String customerName = '',
    String phone = '',
    String? tableId,
    String paymentMethod = '',
  }) async {
    final record = {
      'id': id,
      'restaurantId': restaurantId,
      'tableId': tableId ?? id,
      'cartItems': cartItems,
      'customerName': customerName,
      'phone': phone,
      'paymentMethod': paymentMethod,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      await posOfflineStore.putActiveOrder(record);
    } catch (error) {
      debugPrint('POS IndexedDB cart save failed: $error');
    }
    await PosLocalDrafts.saveCartDraft(
      restaurantId: restaurantId,
      cartId: id,
      cartItems: cartItems,
      customerName: customerName,
      phone: phone,
      paymentMethod: paymentMethod,
    );
  }

  Future<void> clearActiveOrder(String id, {String? restaurantId}) async {
    try {
      await posOfflineStore.deleteActiveOrder(id);
    } catch (_) {}
    if (restaurantId != null && restaurantId.isNotEmpty) {
      await PosLocalDrafts.clearCartDraft(
        restaurantId: restaurantId,
        cartId: id,
      );
    }
  }

  Future<Map<String, dynamic>?> loadActiveOrder(
    String id, {
    String? restaurantId,
  }) async {
    try {
      final row = await posOfflineStore.getActiveOrder(id);
      if (row != null) return row;
    } catch (_) {}
    if (restaurantId == null || restaurantId.isEmpty) return null;
    return PosLocalDrafts.loadCartDraft(
      restaurantId: restaurantId,
      cartId: id,
    );
  }

  Future<void> cacheShift(ShiftSession shift) async {
    await posOfflineStore.putShiftState({
      ...shift.toJson(),
      'id': 'current',
      'shiftId': shift.id,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<ShiftSession?> loadCachedShift() async {
    final row = await posOfflineStore.getShiftState('current');
    if (row == null) return null;
    return ShiftSession.fromJson(row);
  }

  Future<Order> commitPosSale(
    Order order, {
    required String restaurantId,
  }) async {
    final reachable = _online || await ApiService.instance.isOnline();
    if (reachable) {
      try {
        final created = await ApiService.instance.createOrder(
          order,
          restaurantId: restaurantId,
        );
        await OrdersDemoService.registerOrder(created);
        unawaited(_mirrorOrder(created, restaurantId: restaurantId));
        unawaited(OrdersDemoService.refreshFromApi());
        return created;
      } catch (error) {
        debugPrint('POS live sale sync failed, queueing: $error');
      }
    }
    final txId = (order.offlineTxId ?? order.id);
    final payload = order.toMap()
      ..['id'] = order.id
      ..['restaurantId'] = restaurantId
      ..['restaurant_id'] = restaurantId
      ..['offline_tx_id'] = txId
      ..['offlineTxId'] = txId;
    final queueRow = {
      'id': txId,
      'type': 'pos_sale',
      'createdAt': order.createdAt.toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'status': 'pending_sync',
      'restaurantId': restaurantId,
      'payload': payload,
    };
    await posOfflineStore.putQueueItem(queueRow);
    await PosLocalDrafts.upsertPendingOrder(queueRow);
    await OrdersDemoService.registerOrder(order);
    await refreshPendingCount();
    unawaited(flushQueue());
    return order;
  }

  Future<Order> commitDineInCheckout({
    required Order order,
    required String restaurantId,
    required String tableId,
    required List<CartItem> cartItems,
    required String paymentMethod,
    String? customerName,
    String? phone,
    String? invoiceNumber,
    double? tipAmount,
  }) async {
    final reachable = _online || await ApiService.instance.isOnline();
    if (reachable) {
      try {
        final result = await DiningTablesService.instance.checkout(
          tableId,
          cartItems: cartItems,
          paymentMethod: paymentMethod,
          customerName: customerName,
          phone: phone,
          invoiceNumber: invoiceNumber,
          orderId: order.offlineTxId ?? order.id,
          offlineTxId: order.offlineTxId ?? order.id,
          shiftId: order.shiftId,
          cashierId: order.cashierId,
          cashierName: order.cashierName,
          tipAmount: tipAmount,
        );
        // The server checkout is the authoritative operation. Local cache,
        // mirroring and history refresh must not delay releasing the table UI.
        unawaited(OrdersDemoService.registerOrder(result.order));
        unawaited(_mirrorOrder(result.order, restaurantId: restaurantId));
        unawaited(clearActiveOrder(tableId, restaurantId: restaurantId));
        unawaited(OrdersDemoService.refreshFromApi());
        return result.order;
      } catch (error) {
        debugPrint('POS dine-in live checkout failed, queueing: $error');
      }
    }
    final txId = order.offlineTxId ?? order.id;
    final queueRow = {
      'id': txId,
      'type': 'dine_in_checkout',
      'createdAt': order.createdAt.toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'status': 'pending_sync',
      'restaurantId': restaurantId,
      'tableId': tableId,
      'payload': {
        ...order.toMap(),
        'id': order.id,
        'offline_tx_id': txId,
        'offlineTxId': txId,
        'type': 'dine_in_checkout',
        'tableId': tableId,
        'paymentMethod': paymentMethod,
        'invoiceNumber': invoiceNumber,
        'customerName': customerName,
        'phone': phone,
        if (tipAmount != null) 'tipAmount': tipAmount,
        'cartItems': cartItems
            .map(DiningTablesService.cartItemToSessionMap)
            .toList(),
      },
    };
    await posOfflineStore.putQueueItem(queueRow);
    await PosLocalDrafts.upsertPendingOrder(queueRow);
    unawaited(OrdersDemoService.registerOrder(order));
    unawaited(clearActiveOrder(tableId, restaurantId: restaurantId));
    unawaited(refreshPendingCount());
    unawaited(flushQueue());
    return order;
  }

  Future<void> flushQueue() async {
    if (_syncing || !_online) return;
    _syncing = true;
    notifyListeners();
    try {
      final pending = await posOfflineStore.listQueuePending();
      final drafts = await PosLocalDrafts.listPendingOrders();
      final byId = <String, Map<String, dynamic>>{};
      for (final row in [...pending, ...drafts]) {
        final id = row['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        byId.putIfAbsent(id, () => Map<String, dynamic>.from(row));
      }
      for (final row in byId.values) {
        final id = row['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final payload = row['payload'];
        if (payload is! Map) continue;
        try {
          await posOfflineStore.putQueueItem({
            ...row,
            'status': 'syncing',
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          });
          final payloadMap = Map<String, dynamic>.from(payload);
          final type =
              row['type']?.toString() ??
              payloadMap['type']?.toString() ??
              'pos_sale';
          if (type == 'dine_in_checkout') {
            await _flushDineInCheckout(row, payloadMap);
          } else {
            final order = Order.fromMap(id, payloadMap);
            final created = await ApiService.instance.createOrder(
              order,
              restaurantId:
                  row['restaurantId']?.toString() ??
                  ApiService.defaultRestaurantId,
            );
            await OrdersDemoService.registerOrder(created);
            unawaited(
              _mirrorOrder(
                created,
                restaurantId: row['restaurantId']?.toString(),
              ),
            );
          }
          await posOfflineStore.deleteQueueItem(id);
          await PosLocalDrafts.removePendingOrder(id);
        } catch (error) {
          final failed = {
            ...row,
            'status': 'pending_sync',
            'lastError': error.toString(),
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          };
          await posOfflineStore.putQueueItem(failed);
          await PosLocalDrafts.upsertPendingOrder(failed);
          final unreachable =
              error.toString().contains('مهلة') ||
              error.toString().contains('الاتصال') ||
              error.toString().contains('Socket') ||
              error.toString().contains('Failed host');
          if (unreachable) {
            _online = false;
            break;
          }
        }
      }
      if (_online) {
        final last = _lastCatalogRefresh;
        if (last == null ||
            DateTime.now().difference(last) > const Duration(minutes: 2)) {
          unawaited(_refreshCatalogFromCloud());
        }
      }
    } finally {
      _syncing = false;
      await refreshPendingCount();
    }
  }

  Future<void> _refreshCatalogFromCloud() async {
    try {
      final restaurantId =
          AdminAuthService.instance.restaurantId ??
          ApiService.defaultRestaurantId;
      final page = await ApiService.instance.fetchItemsPage(
        restaurantId: restaurantId,
        lite: true,
        limit: 250,
      );
      await cacheCatalog(restaurantId, page.items);
      _lastCatalogRefresh = DateTime.now();
    } catch (_) {}
  }

  Future<void> _flushDineInCheckout(
    Map<String, dynamic> row,
    Map<String, dynamic> payload,
  ) async {
    final tableId =
        row['tableId']?.toString() ?? payload['tableId']?.toString() ?? '';
    final restaurantId =
        row['restaurantId']?.toString() ?? ApiService.defaultRestaurantId;
    final txId =
        row['id']?.toString() ?? payload['offline_tx_id']?.toString() ?? '';
    final cartRaw = payload['cartItems'];
    final cartItems = cartRaw is List
        ? DiningTablesService.cartItemsFromSession(
            cartRaw
                .whereType<Map>()
                .map((entry) => Map<String, dynamic>.from(entry))
                .toList(),
          )
        : <CartItem>[];
    if (tableId.isNotEmpty) {
      try {
        final result = await DiningTablesService.instance.checkout(
          tableId,
          cartItems: cartItems,
          paymentMethod: payload['paymentMethod']?.toString() ?? 'كاش',
          customerName: payload['customerName']?.toString(),
          phone: payload['phone']?.toString(),
          invoiceNumber: payload['invoiceNumber']?.toString(),
          orderId: txId,
          offlineTxId: txId,
          shiftId:
              payload['shiftId']?.toString() ?? payload['shift_id']?.toString(),
          cashierId:
              payload['cashierId']?.toString() ??
              payload['cashier_id']?.toString(),
          cashierName:
              payload['cashierName']?.toString() ??
              payload['cashier_name']?.toString(),
          tipAmount:
              (payload['tipAmount'] as num?)?.toDouble() ??
              (payload['tip_amount'] as num?)?.toDouble(),
        );
        await OrdersDemoService.registerOrder(result.order);
        unawaited(_mirrorOrder(result.order, restaurantId: restaurantId));
        return;
      } catch (_) {}
    }
    final order = Order.fromMap(txId, payload);
    final created = await ApiService.instance.createOrder(
      order,
      restaurantId: restaurantId,
    );
    await OrdersDemoService.registerOrder(created);
    unawaited(_mirrorOrder(created, restaurantId: restaurantId));
  }

  Future<void> _mirrorOrder(Order order, {String? restaurantId}) async {
    if (!isFirebaseConfigured) return;
    try {
      await FirebaseService().addOrder(order, restaurantId: restaurantId);
    } catch (error) {
      debugPrint('POS Firebase mirror skipped: $error');
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _browser.detach();
    super.dispose();
  }
}
