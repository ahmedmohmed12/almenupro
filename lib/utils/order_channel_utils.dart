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

/// Keeps platform orders in the same newest-first timeline shown by the
/// provider portals. Invoice number is only a deterministic tie-breaker.
int compareOrdersByPlatformTimeDesc(Order a, Order b) {
  final byTime = b.createdAt.toUtc().compareTo(a.createdAt.toUtc());
  if (byTime != 0) return byTime;
  final aNumber =
      int.tryParse((a.invoiceNumber ?? '').replaceAll(RegExp(r'\D'), '')) ?? 0;
  final bNumber =
      int.tryParse((b.invoiceNumber ?? '').replaceAll(RegExp(r'\D'), '')) ?? 0;
  final byInvoice = bNumber.compareTo(aNumber);
  return byInvoice != 0 ? byInvoice : b.id.compareTo(a.id);
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

String _orderSourceKey(Order order) =>
    (order.orderSource ?? '').trim().toLowerCase();

bool isTalabatOrder(Order order) =>
    !isHallTableOrder(order) && _orderSourceKey(order).contains('talabat');

bool isKeetaOrder(Order order) {
  if (isHallTableOrder(order)) return false;
  final source = _orderSourceKey(order);
  return source.contains('keeta') || source.contains('keta');
}

bool isJahezOrder(Order order) =>
    !isHallTableOrder(order) && _orderSourceKey(order).contains('jahez');

/// Customer website, WhatsApp, and QR orders that are not a scraped platform.
bool isWebsiteOrder(Order order) {
  if (isHallTableOrder(order) ||
      isTalabatOrder(order) ||
      isKeetaOrder(order) ||
      isJahezOrder(order)) {
    return false;
  }
  if (order.createdFromPos || isPosOrderSource(order.orderSource)) return false;
  return isOnlineMenuOrder(order);
}

bool isLocalPosOrder(Order order) {
  return !isHallTableOrder(order) &&
      !isTalabatOrder(order) &&
      !isKeetaOrder(order) &&
      !isJahezOrder(order) &&
      !isWebsiteOrder(order);
}

/// Left the new-order inbox, so it can be filed under its source.
bool hasLeftNewOrderInbox(Order order) =>
    !order.isNewForAdmin &&
    order.status != OrderStatus.pending &&
    order.status != OrderStatus.scheduled;

/// Held until [Order.resolvedAutoReleaseTime]. Kept off the live boards.
bool isScheduledHoldOrder(Order order) => order.status == OrderStatus.scheduled;

List<Order> scheduledHoldOrders(Iterable<Order> orders) {
  final list = orders.where(isScheduledHoldOrder).toList()
    ..sort((a, b) {
      final left = a.resolvedAutoReleaseTime ?? a.targetDeliveryTime ?? a.createdAt;
      final right = b.resolvedAutoReleaseTime ?? b.targetDeliveryTime ?? b.createdAt;
      return left.compareTo(right);
    });
  return list;
}

List<Order> withoutScheduledHolds(Iterable<Order> orders) {
  return orders.where((order) => !isScheduledHoldOrder(order)).toList();
}

List<Order> ordersForSource(
  Iterable<Order> orders,
  bool Function(Order order) test,
) {
  final list = orders.where(test).where(hasLeftNewOrderInbox).toList()
    ..sort(compareOrdersByPlatformTimeDesc);
  return list;
}

/// Every saved Talabat, Keeta, or Jahez invoice from launch through today.
List<Order> ordersForPlatform(
  Iterable<Order> orders,
  bool Function(Order order) test,
) {
  final list = orders.where(test).toList()
    ..sort(compareOrdersByPlatformTimeDesc);
  return list;
}

/// Tab order shared by the cashier and admin order boards.
List<String> orderInboxTabKeys({
  required bool hall,
  required bool handoff,
}) {
  return [
    'new',
    'current',
    'scheduled',
    'talabat',
    'keeta',
    'jahez',
    'website',
    if (hall) 'hall',
    'previous',
    if (handoff) 'handoff',
  ];
}

bool orderMatchesInboxQuery(Order order, String rawQuery) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return true;
  final bare = query.startsWith('#') ? query.substring(1).trim() : query;
  final digits = bare.replaceAll(RegExp(r'\D'), '');

  bool containsText(String? value) {
    final text = (value ?? '').trim().toLowerCase();
    if (text.isEmpty || bare.isEmpty) return false;
    return text.contains(bare) || '#$text'.contains(query);
  }

  final phoneDigits = order.phone.replaceAll(RegExp(r'\D'), '');
  if (digits.isNotEmpty && phoneDigits.contains(digits)) return true;
  if (containsText(order.phone)) return true;
  if (containsText(order.invoiceNumber)) return true;
  if (containsText(order.externalOrderId)) return true;
  if (containsText(order.id)) return true;
  if (containsText(order.paymentMethod)) return true;
  if (containsText(order.targetKitchenName)) return true;
  if (containsText(order.targetKitchenId)) return true;

  if ((bare.contains('كاش') || bare == 'cash' || bare == 'cod') &&
      order.isCashOnDelivery) {
    return true;
  }
  if (isKnetPaymentMethod(order.paymentMethod) &&
      (bare.contains('كي') || bare.contains('knet') || bare.contains('k-net'))) {
    return true;
  }

  final amounts = <double>[
    order.totalPrice,
    order.customerPayable,
    if (order.subtotal != null) order.subtotal!,
  ];
  for (final amount in amounts) {
    final fixed = amount.toStringAsFixed(3);
    if (fixed.contains(bare) || amount.toString().contains(bare)) return true;
  }
  return false;
}

List<Order> filterOrdersByInboxQuery(List<Order> orders, String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return orders;
  return orders.where((order) => orderMatchesInboxQuery(order, trimmed)).toList();
}

String inboxChannelKey(Order order) {
  if (isHallTableOrder(order)) return 'hall';
  if (isTalabatOrder(order)) return 'talabat';
  if (isKeetaOrder(order)) return 'keeta';
  if (isJahezOrder(order)) return 'jahez';
  if (isWebsiteOrder(order)) return 'website';
  return 'previous';
}
