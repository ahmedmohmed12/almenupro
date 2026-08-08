import '../models/order.dart';

const _onlineSourcePattern = RegExp(
  r'menu|web|whatsapp|direct|online|site|app|qr',
  caseSensitive: false,
);

const _cashPaymentPattern = RegExp(
  r'cash|كاش|cod|cash_on_delivery|نقد|نقداً|نقدا|عند\s*الاستلام',
  caseSensitive: false,
);

bool isPosOrderSource(String? source) {
  return source?.trim().toLowerCase() == 'pos';
}

bool isOnlineMenuOrder(Order order) {
  if (isPosOrderSource(order.orderSource)) return false;
  if (order.status == OrderStatus.delivered &&
      order.shiftId != null &&
      order.shiftId!.isNotEmpty) {
    return false;
  }
  final source = order.orderSource?.trim().toLowerCase() ?? '';
  if (source.isEmpty) return true;
  return _onlineSourcePattern.hasMatch(source) || !isPosOrderSource(source);
}

bool isCashPaymentMethod(String? paymentMethod) {
  final value = paymentMethod?.trim() ?? '';
  if (value.isEmpty) return false;
  return _cashPaymentPattern.hasMatch(value);
}

bool isOnlineCashOrder(Order order) {
  return isOnlineMenuOrder(order) && isCashPaymentMethod(order.paymentMethod);
}

int countPendingOnlineOrders(Iterable<Order> orders) {
  return orders
      .where(
        (order) =>
            order.status == OrderStatus.pending && isOnlineMenuOrder(order),
      )
      .length;
}
