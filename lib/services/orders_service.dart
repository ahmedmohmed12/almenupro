import 'package:flutter/foundation.dart';

import '../models/cart_item.dart';
import '../models/delivery_address_details.dart';
import '../models/order.dart';
import '../utils/firebase_config.dart';
import 'firebase_service.dart';
import 'orders_demo_service.dart';
import 'api_service.dart';

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

  Future<void> updateOrderStatus(
    String orderId,
    OrderStatus status, {
    String? shiftId,
    String? cashierId,
  }) async {
    if (usesFirebase) {
      await _firebase.updateOrderStatus(
        orderId,
        status,
        shiftId: shiftId,
        cashierId: cashierId,
      );
      return;
    }
    await OrdersDemoService.updateOrderStatus(
      orderId,
      status,
      shiftId: shiftId,
      cashierId: cashierId,
    );
  }

  Future<void> refreshOrders() async {
    if (usesFirebase) {
      await _firebase.refreshOrders();
      return;
    }
    await OrdersDemoService.refreshFromApi();
  }

  Future<void> submitOrderFromCart({
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
    );

    final created = await ApiService.instance.createOrder(
      order,
      restaurantId: restaurantId ?? ApiService.defaultRestaurantId,
    );
    await OrdersDemoService.registerOrder(created);
    await OrdersDemoService.refreshFromApi();

    if (usesFirebase) {
      try {
        await _firebase.addOrder(created);
      } catch (error) {
        debugPrint('Firebase order mirror skipped: $error');
      }
    }
  }
}
