import '../models/order.dart';

Future<String> requestBrowserNotificationPermission() async {
  return 'unsupported';
}

Future<String> browserNotificationPermissionStatus() async {
  return 'unsupported';
}

Future<void> showNewOrderBrowserNotification(Order order) async {}

bool get browserNotificationsSupported => false;
