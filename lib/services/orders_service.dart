import '../models/cart_item.dart';
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
    if (usesFirebase) return _firebase.watchOrders();
    return OrdersDemoService.watchOrders();
  }

  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    if (usesFirebase) {
      await _firebase.updateOrderStatus(orderId, status);
      return;
    }
    await OrdersDemoService.updateOrderStatus(orderId, status);
  }

  Future<void> submitOrderFromCart({
    required List<CartItem> cartItems,
    required String customerName,
    required String phone,
    required String address,
    required String paymentMethod,
    required String invoiceNumber,
  }) async {
    final order = OrdersDemoService.orderFromCart(
      cartItems: cartItems,
      customerName: customerName,
      phone: phone,
      address: address,
      paymentMethod: paymentMethod,
      invoiceNumber: invoiceNumber,
    );

    if (usesFirebase) {
      await _firebase.addOrder(order);
      return;
    }

    final created = await ApiService.instance.createOrder(order);
    await OrdersDemoService.registerOrder(created);
    await OrdersDemoService.refreshFromApi();
  }
}
