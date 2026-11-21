import '../models/order.dart';

import 'pos_pending_orders.dart'
    show isPendingPosPickupOrder, pendingPosPickupOrders;

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
  // Kept for shift revenue + legacy callers; prefer pos_pending_orders.dart.
  return isPendingPosPickupOrder(order);
}

/// Unpaid held pickup orders still open at the counter.
bool countsTowardShiftRevenue(Order order) {
  if (order.status == OrderStatus.cancelled) return false;
  if (isPendingPickupPayment(order)) return false;
  return true;
}

List<Order> unsettledPickupOrders(Iterable<Order> orders) =>
    pendingPosPickupOrders(orders);