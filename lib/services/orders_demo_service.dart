import 'dart:async';

import '../models/cart_item.dart';
import '../models/delivery_address_details.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import 'api_service.dart';

/// Local/demo orders shown when Firebase is not configured.
class OrdersDemoService {
  OrdersDemoService._();

  static final _controller = StreamController<List<Order>>.broadcast();
  static List<Order> _orders = [];
  static var _initialized = false;
  static var isDemoData = true;
  static Timer? _pollTimer;
  static Timer? _simulationTimer;

  static Stream<List<Order>> watchOrders() {
    unawaited(_ensureInitialized());
    return _controller.stream;
  }

  static bool get hasOrders => _orders.isNotEmpty;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    await _refreshFromApi();

    if (_orders.isEmpty) {
      try {
        final menuItems = await ApiService.instance.fetchMenuItems();
        _orders = _buildMockOrders(menuItems);
      } catch (_) {
        _orders = _buildMockOrders(const []);
      }
      isDemoData = true;
      _emit();
      _scheduleDemoSimulation();
    }

    _pollTimer ??= Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_refreshFromApi());
    });
  }

  static Future<void> refreshFromApi() => _refreshFromApi();

  static Future<void> _refreshFromApi() async {
    try {
      final apiOrders = await ApiService.instance.fetchOrders();
      if (apiOrders.isEmpty) {
        if (_orders.isEmpty) return;
        if (!isDemoData) {
          _orders = [];
          isDemoData = true;
          _emit();
        }
        return;
      }

      isDemoData = false;
      _orders = apiOrders;
      _emit();
    } catch (_) {}
  }

  static Future<void> updateOrderStatus(
    String orderId,
    OrderStatus status, {
    String? shiftId,
    String? cashierId,
  }) async {
    await _ensureInitialized();

    final index = _orders.indexWhere((order) => order.id == orderId);
    if (index == -1) return;

    if (!orderId.startsWith('demo-')) {
      try {
        await ApiService.instance.updateOrderStatus(
          orderId,
          status,
          shiftId: shiftId,
          cashierId: cashierId,
        );
      } catch (_) {}
    }

    _orders[index] = _orders[index].copyWith(
      status: status,
      shiftId: shiftId,
      cashierId: cashierId,
    );
    _emit();
  }

  static Future<void> registerOrder(Order order) async {
    await _ensureInitialized();

    if (!order.id.startsWith('demo-')) {
      _orders = [order, ..._orders.where((item) => item.id != order.id)];
      isDemoData = false;
    } else {
      _orders = [order, ..._orders];
    }
    _emit();
  }

  static void _emit() {
    if (_controller.isClosed) return;
    _controller.add(List.unmodifiable(_orders));
  }

  static void _scheduleDemoSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = Timer(const Duration(seconds: 45), () {
      if (!isDemoData || _orders.any((order) => order.id == 'demo-live')) {
        return;
      }

      final now = DateTime.now();
      _orders = [
        Order(
          id: 'demo-live',
          customerName: 'عبدالله الرشيد',
          phone: '96599887766',
          address: 'السالمية، قطعة 12، شارع سالم المبارك',
          items: const [
            OrderLineItem(
              menuItemId: '1962105681',
              name: 'مينى بايتس كيندر',
              unitPrice: 7,
              quantity: 1,
              selectedOptions: [],
            ),
          ],
          totalPrice: 7,
          orderType: OrderType.delivery,
          status: OrderStatus.pending,
          createdAt: now,
          invoiceNumber: now.millisecondsSinceEpoch.toString().substring(5),
          paymentMethod: 'K-Net',
        ),
        ..._orders,
      ];
      _emit();
    });
  }

  static List<Order> _buildMockOrders(List<MenuItem> menuItems) {
    MenuItem pick(int index, String fallbackName, double fallbackPrice) {
      if (menuItems.isEmpty) {
        return MenuItem(
          id: index,
          categoryId: 1,
          categoryName: 'كوكيز',
          name: fallbackName,
          description: '',
          price: fallbackPrice,
          imageUrl: '',
          isAvailable: true,
        );
      }
      return menuItems[index % menuItems.length];
    }

    OrderLineItem line(MenuItem item, int qty) {
      return OrderLineItem(
        menuItemId: item.id.toString(),
        name: item.name,
        unitPrice: item.price,
        quantity: qty,
        selectedOptions: const [],
      );
    }

    final now = DateTime.now();
    final item1 = pick(0, 'مينى بايتس كيندر', 7);
    final item2 = pick(1, 'كوكيز شوكولاتة كيندر', 6.5);
    final item3 = pick(2, 'مولتن نوتيلا', 6.5);
    final lines1 = [line(item1, 1), line(item2, 2)];
    final lines2 = [line(item3, 2)];
    final total1 = lines1.fold<double>(0, (sum, item) => sum + item.lineTotal);
    final total2 = lines2.fold<double>(0, (sum, item) => sum + item.lineTotal);

    return [
      Order(
        id: 'demo-1',
        customerName: 'نورة المطيري',
        phone: '96555001122',
        address: 'الجابرية، قطعة 3، شارع 12',
        items: lines1,
        totalPrice: total1,
        orderType: OrderType.delivery,
        status: OrderStatus.pending,
        createdAt: now.subtract(const Duration(minutes: 8)),
        invoiceNumber: '874521',
        paymentMethod: 'كاش',
      ),
      Order(
        id: 'demo-2',
        customerName: 'محمد العنزي',
        phone: '96566778899',
        address: 'حولي، شارع تونس',
        items: lines2,
        totalPrice: total2,
        orderType: OrderType.delivery,
        status: OrderStatus.confirmed,
        createdAt: now.subtract(const Duration(minutes: 24)),
        invoiceNumber: '874498',
        paymentMethod: 'K-Net',
      ),
      Order(
        id: 'demo-3',
        customerName: 'فاطمة الشمري',
        phone: '96599112233',
        address: 'الفروانية، جليب الشيوخ',
        items: [line(pick(3, 'مينى بايتس ميكس', 5.2), 1)],
        totalPrice: pick(3, 'مينى بايتس ميكس', 5.2).price,
        orderType: OrderType.pickup,
        status: OrderStatus.preparing,
        createdAt: now.subtract(const Duration(hours: 1, minutes: 10)),
        invoiceNumber: '874450',
        paymentMethod: 'كاش',
      ),
      Order(
        id: 'demo-4',
        customerName: 'خالد السبيعي',
        phone: '96555443322',
        address: 'مشرف، قطعة 1',
        items: [line(pick(4, 'كوكيز نوتيلا', 6.5), 3)],
        totalPrice: pick(4, 'كوكيز نوتيلا', 6.5).price * 3,
        orderType: OrderType.delivery,
        status: OrderStatus.delivered,
        createdAt: now.subtract(const Duration(hours: 3)),
        invoiceNumber: '874401',
        paymentMethod: 'K-Net',
      ),
    ];
  }

  static Order orderFromCart({
    required List<CartItem> cartItems,
    required String customerName,
    required String phone,
    required String address,
    required String paymentMethod,
    required String invoiceNumber,
    double? deliveryFee,
    String? governorate,
    String? areaName,
    String? deliveryZoneId,
    DeliveryAddressDetails? addressDetails,
    String? orderSource,
    OrderType? orderType,
    double? walletRedeemAmount,
    double? subtotal,
    double? discountAmount,
    String? offerId,
    String? offerTitle,
  }) {
    final items = cartItems.map(OrderLineItem.fromCartItem).toList();
    final charged =
        cartItems.fold<double>(0, (sum, item) => sum + item.totalPrice);
    final listed =
        cartItems.fold<double>(0, (sum, item) => sum + item.listedTotalPrice);
    final fee = deliveryFee ?? 0;
    final discount = discountAmount ??
        ((listed > charged) ? listed - charged : 0);
    final netSubtotal = (subtotal ?? charged);

    return Order(
      id: 'pending',
      customerName: customerName,
      phone: phone,
      address: address,
      items: items,
      subtotal: listed > 0 ? listed : netSubtotal,
      deliveryFee: deliveryFee,
      discountAmount: discount > 0 ? discount : null,
      offerId: offerId,
      offerTitle: offerTitle,
      totalPrice: netSubtotal + fee,
      orderType: orderType ?? OrderType.delivery,
      status: OrderStatus.pending,
      createdAt: DateTime.now(),
      invoiceNumber: invoiceNumber,
      paymentMethod: paymentMethod,
      governorate: governorate,
      areaName: areaName,
      deliveryZoneId: deliveryZoneId,
      addressDetails: addressDetails ?? const DeliveryAddressDetails(),
      orderSource: orderSource,
      walletRedeemAmount: walletRedeemAmount,
    );
  }
}
