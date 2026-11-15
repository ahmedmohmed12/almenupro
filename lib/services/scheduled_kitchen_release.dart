import 'package:flutter/foundation.dart';

import '../models/order.dart';
import '../models/order_alert_sound.dart';
import '../models/scheduled_order.dart';
import 'order_alert_sound_service.dart';
import 'orders_demo_service.dart';
import 'orders_service.dart';
import 'pos_print_helper.dart';
import '../utils/pos_receipt_html.dart';

/// Distinct kitchen alert plus the saved invoice ticket.
Future<void> dispatchScheduledKitchenRelease(ScheduledOrder hold) async {
  try {
    await OrderAlertSoundService.instance.previewSound(OrderAlertSoundType.alarm);
  } catch (error) {
    debugPrint('scheduled alert sound failed: $error');
  }

  var ticket = hold.toKitchenTicket();
  try {
    final index = OrdersDemoService.loadedOrders.indexWhere(
      (order) => order.id == hold.id,
    );
    if (index >= 0) {
      final live = OrdersDemoService.loadedOrders[index];
      await OrdersService.instance.updateOrderStatus(
        live.id,
        OrderStatus.inKitchen,
      );
      ticket = live.copyWith(status: OrderStatus.inKitchen);
    }
  } catch (error) {
    debugPrint('scheduled status update failed: $error');
  }

  try {
    await PosPrintHelper.printOrder(
      order: ticket,
      kind: PosReceiptKind.kitchen,
      ignorePermission: true,
    );
  } catch (error) {
    debugPrint('scheduled kitchen print failed: $error');
  }
}
