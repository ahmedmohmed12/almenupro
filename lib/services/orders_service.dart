import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/cart_item.dart';
import '../models/delivery_address_details.dart';
import '../models/order.dart';
import '../models/order_platform.dart';
import '../utils/firebase_config.dart';
import '../utils/order_payment_utils.dart';
import 'firebase_service.dart';
import 'orders_demo_service.dart';
import 'api_service.dart';
import 'offline/pos_sync_service.dart';

/// Unified orders access for admin dashboard and checkout.
class OrdersService {
  OrdersService._();

  static final OrdersService instance = OrdersService._();

  final FirebaseService _firebase = FirebaseService();

  bool get usesFirebase => isFirebaseConfigured;
  bool get isDemoMode => !usesFirebase && OrdersDemoService.isDemoData;

  Stream<List<Order>> watchOrders() {
    return OrdersDemoService.watchOrders();
  }

  Future<void> resumeRealtime() => OrdersDemoService.resumeRealtime();

  Future<void> updateOrderStatus(
    String orderId,
    OrderStatus status, {
    String? shiftId,
    String? cashierId,
    String? cashierName,
    bool autoAccepted = false,
    String? acceptedBy,
    String? acceptedByName,
  }) async {
    await OrdersDemoService.updateOrderStatus(
      orderId,
      status,
      shiftId: shiftId,
      cashierId: cashierId,
      cashierName: cashierName,
      autoAccepted: autoAccepted,
      acceptedBy: acceptedBy,
      acceptedByName: acceptedByName,
    );
    if (usesFirebase) {
      try {
        await _firebase.updateOrderStatus(
          orderId,
          status,
          shiftId: shiftId,
          cashierId: cashierId,
          cashierName: cashierName,
          autoAccepted: autoAccepted,
          acceptedBy: acceptedBy,
          acceptedByName: acceptedByName,
        );
      } catch (error) {
        debugPrint('Firebase order status mirror skipped: $error');
      }
    }
  }

  Future<void> refreshOrders() async {
    await OrdersDemoService.refreshFromApi();
  }

  Future<Order> submitOrderFromCart({
    required List<CartItem> cartItems,
    required String customerName,
    required String phone,
    required String address,
    required String paymentMethod,
    required String invoiceNumber,
    String? restaurantId,
    double? deliveryFee,
    String? governorate,
    String? areaName,
    String? deliveryZoneId,
    DeliveryAddressDetails? addressDetails,
    String? orderSource,
    OrderType? orderType,
    PlatformOrderMeta? platformMeta,
    double? walletRedeemAmount,
    double? subtotal,
    double? discountAmount,
    String? offerId,
    String? offerTitle,
    String? targetKitchenId,
    String? targetKitchenName,
    bool refreshList = true,
    bool offlineFirst = false,
    String? shiftId,
    String? cashierId,
    String? cashierName,
    String? tableId,
    OrderStatus? status,
    DateTime? deliveryDate,
    DateTime? targetDeliveryTime,
    int? prepTimeMinutes,
    int? routeTimeMinutes,
    int? cashierBufferMinutes,
    DateTime? autoReleaseTime,
    String? paymentStatus,
    String? heldShiftId,
    DateTime? paidAt,
  }) async {
    final order = OrdersDemoService.orderFromCart(
      cartItems: cartItems,
      customerName: customerName,
      phone: phone,
      address: address,
      paymentMethod: paymentMethod,
      invoiceNumber: invoiceNumber,
      deliveryFee: deliveryFee,
      governorate: governorate,
      areaName: areaName,
      deliveryZoneId: deliveryZoneId,
      addressDetails: addressDetails,
      orderSource: orderSource,
      orderType: orderType,
      externalOrderId: platformMeta?.externalOrderId,
      platformCommission: platformMeta?.platformCommission,
      walletRedeemAmount: walletRedeemAmount,
      subtotal: subtotal,
      discountAmount: discountAmount,
      offerId: offerId,
      offerTitle: offerTitle,
      targetKitchenId: targetKitchenId,
      targetKitchenName: targetKitchenName,
      shiftId: shiftId,
      cashierId: cashierId,
      cashierName: cashierName,
      tableId: tableId,
      initialStatus:
          status ?? (offlineFirst ? OrderStatus.confirmed : OrderStatus.pending),
      createdFromPos: offlineFirst,
      deliveryDate: deliveryDate,
      targetDeliveryTime: targetDeliveryTime,
      prepTimeMinutes: prepTimeMinutes,
      routeTimeMinutes: routeTimeMinutes,
      cashierBufferMinutes: cashierBufferMinutes,
      autoReleaseTime: autoReleaseTime,
      paymentStatus: paymentStatus,
      heldShiftId: heldShiftId,
      paidAt: paidAt,
    );

    if (offlineFirst) {
      final saved = await PosSyncService.instance.commitPosSale(
        order,
        restaurantId: restaurantId ?? ApiService.defaultRestaurantId,
      );
      unawaited(refreshOrders());
      return saved;
    }

    final created = await ApiService.instance.createOrder(
      order,
      restaurantId: restaurantId ?? ApiService.defaultRestaurantId,
    );
    await OrdersDemoService.registerOrder(created);
    if (refreshList) {
      unawaited(OrdersDemoService.refreshFromApi());
    }

    unawaited(mirrorOrder(created, restaurantId: restaurantId));
    return created;
  }

  Future<Order> submitHeldPickupFromCart({
    required List<CartItem> cartItems,
    required String customerName,
    required String phone,
    required String invoiceNumber,
    String? restaurantId,
    String? shiftId,
    String? cashierId,
    String? cashierName,
  }) {
    return submitOrderFromCart(
      cartItems: cartItems,
      customerName: customerName,
      phone: phone,
      address: 'استلام من المحل',
      paymentMethod: 'غير مدفوع',
      invoiceNumber: invoiceNumber,
      restaurantId: restaurantId,
      orderSource: 'pos',
      orderType: OrderType.pickup,
      offlineFirst: true,
      shiftId: shiftId,
      cashierId: cashierId,
      cashierName: cashierName,
      paymentStatus: OrderPaymentStatus.pending.storageValue,
      heldShiftId: shiftId,
    );
  }

  Future<Order> settleHeldPickupOrder({
    required Order order,
    required String paymentMethod,
    required List<CartItem> cartItems,
    required String restaurantId,
    String? shiftId,
    String? cashierId,
    String? cashierName,
    String? managerPin,
    String? kitchenVoidReason,
  }) async {
    final subtotal = cartItems.fold<double>(
      0,
      (sum, item) => sum + item.totalPrice,
    );
    final settled = order.copyWith(
      items: cartItems.map(OrderLineItem.fromCartItem).toList(),
      subtotal: subtotal,
      totalPrice: subtotal,
      paymentMethod: paymentMethod,
      paymentStatus: OrderPaymentStatus.paid.storageValue,
      paidAt: DateTime.now().toUtc(),
      status: OrderStatus.delivered,
      shiftId: shiftId ?? order.shiftId,
      cashierId: cashierId ?? order.cashierId,
      cashierName: cashierName ?? order.cashierName,
      heldShiftId: order.heldShiftId ?? order.shiftId,
    );

    try {
      final saved = await ApiService.instance.settlePickupOrder(
        settled,
        restaurantId: restaurantId,
        shiftId: shiftId,
        cashierId: cashierId,
        cashierName: cashierName,
        managerPin: managerPin,
        kitchenVoidReason: kitchenVoidReason,
      );
      final resolved = saved ?? settled;
      OrdersDemoService.replaceVisibleOrder(resolved);
      unawaited(OrdersDemoService.refreshFromApi());
      return resolved;
    } catch (error) {
      debugPrint('Pickup settle API failed, applying locally: $error');
      OrdersDemoService.replaceVisibleOrder(settled);
      unawaited(mirrorOrder(settled, restaurantId: restaurantId));
      return settled;
    }
  }

  Future<Order> saveScheduledInvoice(Order order, {String? restaurantId}) async {
    OrdersDemoService.replaceVisibleOrder(order);
    try {
      await ApiService.instance.createOrder(
        order,
        restaurantId: restaurantId ?? ApiService.defaultRestaurantId,
        bumpUpdatedAt: true,
      );
      return order;
    } catch (_) {
      return order;
    }
  }

  Future<void> mirrorOrder(Order order, {String? restaurantId}) async {
    if (!usesFirebase) return;
    try {
      await _firebase.addOrder(order, restaurantId: restaurantId);
    } catch (error) {
      debugPrint('Firebase order mirror skipped: $error');
    }
  }
}
