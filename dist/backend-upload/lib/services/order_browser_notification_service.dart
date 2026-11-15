import '../models/order.dart';
import 'order_browser_notification_stub.dart'
    if (dart.library.html) 'order_browser_notification_web.dart';

export 'order_browser_notification_stub.dart'
    if (dart.library.html) 'order_browser_notification_web.dart';

class OrderBrowserNotificationService {
  OrderBrowserNotificationService._();

  static final OrderBrowserNotificationService instance =
      OrderBrowserNotificationService._();

  bool get isSupported => browserNotificationsSupported;

  Future<String> permissionStatus() => browserNotificationPermissionStatus();

  Future<String> requestPermission() =>
      requestBrowserNotificationPermission();

  Future<void> notifyNewOrder(Order order) =>
      showNewOrderBrowserNotification(order);
}
