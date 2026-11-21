import '../models/cart_item.dart';
import '../services/admin_auth_service.dart';
import '../services/pos_operations_service.dart';

class KitchenVoidReason {
  KitchenVoidReason._();

  static const customerRequest = 'customer_request';
  static const entryMistake = 'entry_mistake';
  static const outOfStock = 'out_of_stock';
  static const kitchenUnable = 'kitchen_unable';
  static const other = 'other';

  static const options = <String, String>{
    customerRequest: 'طلب العميل',
    entryMistake: 'خطأ إدخال',
    outOfStock: 'نفاد المخزون',
    kitchenUnable: 'تعذر في المطبخ',
    other: 'سبب آخر',
  };
}

class KitchenOverrideAuthorization {
  const KitchenOverrideAuthorization({
    required this.managerPin,
    required this.reason,
    this.authorizedById,
    this.authorizedByName,
  });

  final String managerPin;
  final String reason;
  final String? authorizedById;
  final String? authorizedByName;
}

bool posStaffBypassesKitchenLock() {
  if (!AdminAuthService.instance.isCashier) return true;
  final session = PosOperationsService.instance.cashierSession;
  final roleId = session?.roleId ?? '';
  if (roleId == 'shift_supervisor' || roleId == 'pos_admin') return true;
  final permissions = PosOperationsService.instance.effectivePermissions;
  if (permissions['void_orders'] == true) return true;
  if (permissions['manager_override'] == true) return true;
  return false;
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
  if (posStaffBypassesKitchenLock()) return false;
  if (nextQuantity <= 0) return true;
  if (nextQuantity < item.quantity) return true;
  return false;
}