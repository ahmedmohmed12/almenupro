import 'package:almenupro/models/order.dart';
import 'package:almenupro/models/order_payment_line.dart';
import 'package:almenupro/utils/order_payments.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validateSplitPayments requires balanced cash and knet', () {
    final payments = buildSplitPayments(cashAmount: 2, knetAmount: 1.5);
    expect(
      validateSplitPayments(payments: payments, orderTotal: 3.5),
      isNull,
    );
    expect(
      validateSplitPayments(payments: payments, orderTotal: 3.4),
      isNotNull,
    );
  });

  test('shiftPaymentBreakdown reads payments array', () {
    final order = Order(
      id: 'o1',
      customerName: 'Guest',
      phone: '00000000',
      address: 'pickup',
      items: const [],
      totalPrice: 5,
      orderType: OrderType.pickup,
      status: OrderStatus.delivered,
      createdAt: DateTime.utc(2026, 1, 1),
      paymentMethod: 'كاش + كي نت',
      payments: const [
        OrderPaymentLine(method: 'cash', amount: 2),
        OrderPaymentLine(method: 'knet', amount: 3),
      ],
    );
    final split = shiftPaymentBreakdown(order);
    expect(split.cash, 2);
    expect(split.knet, 3);
    expect(isSplitCashKnetOrder(order), isTrue);
  });
}