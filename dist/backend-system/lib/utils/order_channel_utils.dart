import '../models/order.dart';

final _onlineSourcePattern = RegExp(
  r'menu|web|whatsapp|direct|online|site|app|qr',
  caseSensitive: false,
);

final _cashPaymentPattern = RegExp(
  r'cash|كاش|cod|cash_on_delivery|نقد|نقداً|نقدا|عند\s*الاستلام',
  caseSensitive: false,
);

bool isPosOrderSource(String? source) {
  final value = source?.trim().toLowerCase() ?? '';
  if (value.isEmpty) return false;
  return value == 'pos' ||
      value.startsWith('pos-') ||
      value.startsWith('pos_') ||
      value.contains('cashier');
}

bool isOnlineMenuOrder(Order order) {
  if (order.createdFromPos) return false;
  if (isPosOrderSource(order.orderSource)) return false;
  final source = order.orderSource?.trim().toLowerCase() ?? '';
  if (source.isEmpty) return true;
  return _onlineSourcePattern.hasMatch(source) || !isPosOrderSource(source);
}

bool isCashPaymentMethod(String? paymentMethod) {
  final value = paymentMethod?.trim() ?? '';
  if (value.isEmpty) return false;
  return _cashPaymentPattern.hasMatch(value);
}

bool isKnetPaymentMethod(String? paymentMethod) {
  final value = paymentMethod?.trim() ?? '';
  if (value.isEmpty) return false;
  return RegExp(r'k-?net|knet|كي\s*نت', caseSensitive: false).hasMatch(value);
}

bool isOnlineCashOrder(Order order) {
  return isOnlineMenuOrder(order) && isCashPaymentMethod(order.paymentMethod);
}

bool isPendingOnlineMenuOrder(Order order) {
  return order.status == OrderStatus.pending &&
      isOnlineMenuOrder(order) &&
      !order.isDemoOrder;
}

int countPendingOnlineOrders(Iterable<Order> orders) {
  return orders.where(isPendingOnlineMenuOrder).length;
}

/// Orders that should appear in the POS cashier screen tabs.
///
/// We keep `isOnlineMenuOrder` strict (it excludes POS-created orders) so that
/// the admin notification pipeline can stay quiet for POS.
///
/// For the cashier UI, though, POS-created orders must behave like online
/// orders (current -> previous) so we include them here.
bool isCashierMenuOrder(Order order) =>
    order.createdFromPos || isPosOrderSource(order.orderSource) || isOnlineMenuOrder(order);

bool isHallTableOrderSource(String? source) {
  final value = source?.trim().toLowerCase() ?? '';
  if (value.isEmpty) return false;
  return value == 'pos-dine-in' ||
      value == 'qr-dine-in' ||
      value.contains('dine-in') ||
      value.contains('dine_in');
}

/// Dine-in / hall table orders (POS floor or QR table).
bool isHallTableOrder(Order order) {
  if (order.orderType == OrderType.dineIn) return true;
  if ((order.tableId ?? '').trim().isNotEmpty) return true;
  return isHallTableOrderSource(order.orderSource);
}

/// Closed table bills after checkout (تسكير حساب الطاولة).
bool isClosedHallTableOrder(Order order) {
  return order.status == OrderStatus.delivered && isHallTableOrder(order);
}
