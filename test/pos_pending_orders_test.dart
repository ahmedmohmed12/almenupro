import 'package:almenupro/models/order.dart';
import 'package:almenupro/utils/pos_pending_orders.dart';
import 'package:flutter_test/flutter_test.dart';

Order _samplePickup({String? paymentStatus, OrderStatus? status}) {
  return Order(
    id: 'o1',
    customerName: 'Walk-in',
    phone: '00000000',
    address: 'استلام من المحل',
    paymentMethod: 'غير مدفوع',
    totalPrice: 5,
    subtotal: 5,
    items: const [],
    createdAt: DateTime.now(),
    orderType: OrderType.pickup,
    orderSource: 'pos',
    createdFromPos: true,
    paymentStatus: paymentStatus,
    status: status ?? OrderStatus.preparing,
  );
}

void main() {
  test('kitchen pickup with pending payment is pending', () {
    final order = _samplePickup(paymentStatus: 'pending_payment');
    expect(isPendingPosPickupOrder(order), isTrue);
    expect(isPreviousPosWalkInOrder(order), isFalse);
  });

  test('paid pickup is previous not pending', () {
    final order = _samplePickup(
      paymentStatus: 'paid',
      status: OrderStatus.delivered,
    );
    expect(isPendingPosPickupOrder(order), isFalse);
    expect(isPreviousPosWalkInOrder(order), isTrue);
  });

  test('dine-in preparing unpaid is pending', () {
    final order = Order(
      id: 't1',
      customerName: 'طاولة 1',
      phone: '00000000',
      address: 'طاولة 1',
      paymentMethod: 'كاش',
      totalPrice: 3,
      subtotal: 3,
      items: const [],
      createdAt: DateTime.now(),
      orderType: OrderType.dineIn,
      orderSource: 'pos-dine-in',
      createdFromPos: true,
      paymentStatus: 'pending_payment',
      status: OrderStatus.preparing,
      tableId: 'table_1',
    );
    expect(isPendingPosDineInOrder(order), isTrue);
  });
}