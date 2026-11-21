import '../models/order.dart';
import 'order_payment_utils.dart';

bool isPosWalkInSource(Order order) {
  if (order.createdFromPos) return true;
  final source = (order.orderSource ?? '').trim().toLowerCase();
  return source.startsWith('pos') || source.contains('dine');
}

bool hasUnsettledPosPayment(Order order) {
  if (order.status == OrderStatus.cancelled) return false;
  final payment = OrderPaymentStatus.normalize(order.paymentStatus);
  if (payment == OrderPaymentStatus.paid) return false;
  if (payment == OrderPaymentStatus.pending) return true;
  if (order.orderType == OrderType.dineIn || order.orderType == OrderType.pickup) {
    return order.status.isInProgressForCashier ||
        order.status == OrderStatus.pending ||
        order.status == OrderStatus.confirmed;
  }
  return false;
}

/// Open pickup tickets in الطلبات المعلّقة after kitchen send / hold.
bool isPendingPosPickupOrder(Order order) {
  if (order.orderType != OrderType.pickup) return false;
  if (!isPosWalkInSource(order)) return false;
  return hasUnsettledPosPayment(order);
}

/// Open dine-in tickets in الطلبات المعلّقة after send-kitchen.
bool isPendingPosDineInOrder(Order order) {
  if (order.orderType != OrderType.dineIn) return false;
  if (!isPosWalkInSource(order)) return false;
  return hasUnsettledPosPayment(order);
}

bool isPendingPosWalkInOrder(Order order) =>
    isPendingPosPickupOrder(order) || isPendingPosDineInOrder(order);

int countPendingPosWalkInOrders(Iterable<Order> orders) =>
    orders.where(isPendingPosWalkInOrder).length;

List<Order> pendingPosPickupOrders(Iterable<Order> orders) {
  return orders.where(isPendingPosPickupOrder).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

List<Order> pendingPosDineInOrders(Iterable<Order> orders) {
  return orders.where(isPendingPosDineInOrder).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

/// Settled walk-in pickup / table after pay & close → الطلبات السابقة.
bool isPreviousPosWalkInOrder(Order order) {
  if (order.status == OrderStatus.cancelled) return false;
  if (order.orderType != OrderType.pickup &&
      order.orderType != OrderType.dineIn) {
    return false;
  }
  if (!isPosWalkInSource(order)) return false;
  if (hasUnsettledPosPayment(order)) return false;
  return order.status.isArchivedForAdmin ||
      OrderPaymentStatus.normalize(order.paymentStatus) ==
          OrderPaymentStatus.paid;
}

List<Order> previousPosWalkInOrders(Iterable<Order> orders) {
  return orders.where(isPreviousPosWalkInOrder).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}