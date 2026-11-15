import 'dart:html' as html;

import '../models/order.dart';
import '../utils/admin_deep_link.dart';
import 'admin_order_focus_service.dart';

bool get browserNotificationsSupported => html.Notification.supported;

Future<String> browserNotificationPermissionStatus() async {
  if (!browserNotificationsSupported) return 'unsupported';
  return html.Notification.permission ?? 'default';
}

Future<String> requestBrowserNotificationPermission() async {
  if (!browserNotificationsSupported) return 'unsupported';
  final result = await html.Notification.requestPermission();
  return result ?? html.Notification.permission ?? 'default';
}

Future<void> showNewOrderBrowserNotification(Order order) async {
  if (!browserNotificationsSupported) return;
  if (html.Notification.permission != 'granted') return;

  final invoice = order.invoiceNumber ?? order.id.substring(0, 6);
  final body = '${order.customerName}\n${order.phone}\n'
      '${order.totalPrice.toStringAsFixed(3)} د.ك';

  final notification = html.Notification(
    '🔔 طلب جديد #$invoice',
    body: body,
    icon: 'icons/Icon-192.png',
    tag: 'almenupro-order-${order.id}',
    dir: 'rtl',
    lang: 'ar',
  );
  notification.onClick.listen((_) {
    final ref = (order.invoiceNumber ?? order.id).trim();
    html.window.history.pushState(null, '', AdminDeepLink.orderPath(ref));
    AdminOrderFocusService.instance.requestOrder(ref);
  });
}
