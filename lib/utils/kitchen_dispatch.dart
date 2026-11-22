import '../models/cart_item.dart';

class KitchenVoidReason {
  KitchenVoidReason._();

  static const customerRequest = 'customer_request';
  static const entryMistake = 'entry_mistake';
  static const preparationDelay = 'preparation_delay';
  static const outOfStock = 'out_of_stock';
  static const kitchenUnable = 'kitchen_unable';
  static const other = 'other';

  static const options = <String, String>{
    customerRequest: 'طلب العميل',
    entryMistake: 'خطأ إدخال',
    preparationDelay: 'تأخير التحضير',
    outOfStock: 'نفاد المخزون',
    kitchenUnable: 'تعذر في المطبخ',
    other: 'سبب آخر',
  };
}

class KitchenOverrideAuthorization {
  const KitchenOverrideAuthorization({
    this.managerPin = '',
    required this.reason,
    this.authorizedById,
    this.authorizedByName,
    this.approvalRequestId,
    this.cartItemId,
  });

  final String managerPin;
  final String reason;
  final String? authorizedById;
  final String? authorizedByName;
  final String? approvalRequestId;
  final String? cartItemId;

  bool get usedRemoteApproval =>
      (approvalRequestId ?? '').trim().isNotEmpty && managerPin.isEmpty;
}

List<CartItem> stampKitchenDispatched(
  Iterable<CartItem> items, {
  DateTime? sentAt,
}) {
  final ts = sentAt ?? DateTime.now().toUtc();
  return [
    for (final item in items)
      item.isSentToKitchen
          ? item
          : item.copyWith(isSentToKitchen: true, sentToKitchenAt: ts),
  ];
}

bool cartMutationNeedsKitchenOverride({
  required CartItem item,
  required int nextQuantity,
}) {
  if (!item.isSentToKitchen) return false;
  if (nextQuantity <= 0) return true;
  if (nextQuantity < item.quantity) return true;
  return false;
}