import '../models/order.dart';
import 'order_channel_utils.dart';
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

bool orderBelongsToShift(Order order, String shiftId) {
  final id = shiftId.trim();
  if (id.isEmpty) return false;
  return order.shiftId == id || order.heldShiftId == id;
}

bool isShiftBlockingPendingOrder(Order order) {
  if (isPendingPosWalkInOrder(order)) return true;
  return isPendingOnlineMenuOrder(order);
}

class ShiftPendingSnapshot {
  const ShiftPendingSnapshot({
    required this.total,
    required this.pickup,
    required this.dineIn,
    required this.online,
    required this.orders,
  });

  final int total;
  final int pickup;
  final int dineIn;
  final int online;
  final List<Order> orders;

  bool get hasPending => total > 0;
}

ShiftPendingSnapshot pendingOrdersForShift(
  Iterable<Order> orders,
  String shiftId,
) {
  final blocking = orders
      .where(
        (order) =>
            orderBelongsToShift(order, shiftId) &&
            isShiftBlockingPendingOrder(order),
      )
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  var pickup = 0;
  var dineIn = 0;
  var online = 0;
  for (final order in blocking) {
    if (isPendingOnlineMenuOrder(order)) {
      online += 1;
    } else if (order.orderType == OrderType.dineIn) {
      dineIn += 1;
    } else {
      pickup += 1;
    }
  }
  return ShiftPendingSnapshot(
    total: blocking.length,
    pickup: pickup,
    dineIn: dineIn,
    online: online,
    orders: blocking,
  );
}

bool shiftCloseGuardRoleCanBypass(String? roleId) {
  final id = (roleId ?? '').trim().toLowerCase();
  return id == 'shift_supervisor' || id == 'pos_admin' || id == 'manager';
}

bool shiftCloseGuardCashierOnly(String? roleId) {
  final id = (roleId ?? '').trim().toLowerCase();
  return id.isEmpty || id == 'cashier';
}