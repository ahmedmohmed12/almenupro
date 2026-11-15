import '../models/order.dart';

/// POS pickup orders can be held unpaid until the customer pays at pickup.
class OrderPaymentStatus {
  const OrderPaymentStatus._(this.storageValue);

  final String storageValue;

  static const pending = OrderPaymentStatus._('pending_payment');
  static const paid = OrderPaymentStatus._('paid');

  static OrderPaymentStatus? normalize(String? raw) {
    final value = (raw ?? '').trim().toLowerCase().replaceAll('-', '_');
    if (value.isEmpty) return null;
    if (value == 'pending_payment' ||
        value == 'pendingpayment' ||
        value == 'unpaid') {
      return pending;
    }
    if (value == 'paid') return paid;
    return null;
  }
}

bool isPendingPickupPayment(Order order) {
  if (order.orderType != OrderType.pickup) return false;
  if (!order.createdFromPos) return false;
  if (order.status == OrderStatus.cancelled) return false;
  final payment = OrderPaymentStatus.normalize(order.paymentStatus);
  return payment == OrderPaymentStatus.pending;
}

/// Unpaid held pickup orders still open at the counter.
bool countsTowardShiftRevenue(Order order) {
  if (order.status == OrderStatus.cancelled) return false;
  if (isPendingPickupPayment(order)) return false;
  return true;
}

List<Order> unsettledPickupOrders(Iterable<Order> orders) {
  return orders.where(isPendingPickupPayment).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}