import '../models/order.dart';
import '../models/scheduled_order.dart';

enum ScheduledDeskActionKind { kitchenRelease, whatsappReminder, driverNotice }

class ScheduledDeskAction {
  const ScheduledDeskAction({required this.kind, required this.order});

  final ScheduledDeskActionKind kind;
  final ScheduledOrder order;
}

class ScheduledReleasePlan {
  const ScheduledReleasePlan({
    required this.next,
    required this.actions,
    required this.changed,
  });

  final List<ScheduledOrder> next;
  final List<ScheduledDeskAction> actions;
  final bool changed;
}

/// One pass of the hold clock. Safe to run every few seconds.
ScheduledReleasePlan planScheduledRelease(List<ScheduledOrder> orders, DateTime now) {
  final next = <ScheduledOrder>[];
  final actions = <ScheduledDeskAction>[];
  var changed = false;

  for (final order in orders) {
    if (order.status != ScheduledHoldStatus.scheduled) {
      next.add(order);
      continue;
    }

    var current = order;
    final phoneDigits = order.phone.replaceAll(RegExp(r'\D'), '');
    final canRemind = phoneDigits.length >= 8 &&
        order.reminderSentAt == null &&
        !now.isBefore(order.reminderAt) &&
        now.isBefore(order.targetAt);
    if (canRemind) {
      current = current.copyWith(reminderSentAt: now);
      actions.add(ScheduledDeskAction(
        kind: ScheduledDeskActionKind.whatsappReminder,
        order: current,
      ));
      changed = true;
    } else if (order.reminderSentAt == null &&
        phoneDigits.length < 8 &&
        !now.isBefore(order.reminderAt)) {
      current = current.copyWith(reminderSentAt: now);
      changed = true;
    }

    final driverDue = order.kind == ScheduledKind.delivery &&
        current.driverNotifiedAt == null &&
        !now.isBefore(order.driverNoticeAt) &&
        now.isBefore(order.targetAt.add(const Duration(minutes: 20)));
    if (driverDue) {
      current = current.copyWith(driverNotifiedAt: now);
      actions.add(ScheduledDeskAction(
        kind: ScheduledDeskActionKind.driverNotice,
        order: current,
      ));
      changed = true;
    }

    if (!now.isBefore(order.releaseAt)) {
      current = current.copyWith(
        status: ScheduledHoldStatus.inKitchen,
        releasedAt: now,
      );
      actions.add(ScheduledDeskAction(
        kind: ScheduledDeskActionKind.kitchenRelease,
        order: current,
      ));
      changed = true;
    }

    next.add(current);
  }

  return ScheduledReleasePlan(next: next, actions: actions, changed: changed);
}

bool scheduledTableIsLocked(Iterable<ScheduledOrder> orders, String tableNumber, DateTime now) {
  final needle = tableNumber.trim();
  if (needle.isEmpty) return false;
  return orders.any(
    (order) => order.tableNumber.trim() == needle && order.locksTableAt(now),
  );
}

int upcomingScheduledCount(Iterable<ScheduledOrder> orders, DateTime now) {
  final until = now.add(const Duration(hours: 2));
  return orders.where((order) {
    return order.status == ScheduledHoldStatus.scheduled &&
        !order.targetAt.isBefore(now) &&
        !order.targetAt.isAfter(until);
  }).length;
}

String scheduledReminderText(ScheduledOrder order) {
  final clock = _clock(order.targetAt.toLocal());
  if (order.kind == ScheduledKind.dineIn) {
    return 'تذكير من AlMenuPro: حجزكم على الطاولة ${order.tableNumber} الساعة $clock. بانتظاركم.';
  }
  return 'تذكير من AlMenuPro: طلب التوصيل المجدول سيصل حوالي الساعة $clock.';
}

/// Invoices that reached release time and are not already queued by a hold.
List<ScheduledDeskAction> dueScheduledInvoiceActions(
  Iterable<Order> invoices,
  Iterable<ScheduledOrder> holds,
  DateTime now,
) {
  final heldIds = holds
      .where((hold) => hold.status == ScheduledHoldStatus.scheduled)
      .map((hold) => hold.id)
      .toSet();
  final actions = <ScheduledDeskAction>[];
  for (final invoice in invoices) {
    if (invoice.status != OrderStatus.scheduled) continue;
    final release = invoice.resolvedAutoReleaseTime;
    if (release == null || now.isBefore(release)) continue;
    if (heldIds.contains(invoice.id)) continue;
    actions.add(
      ScheduledDeskAction(
        kind: ScheduledDeskActionKind.kitchenRelease,
        order: ScheduledOrder(
          id: invoice.id,
          kind: ScheduledKind.delivery,
          customerName: invoice.customerName,
          phone: invoice.phone,
          targetAt: invoice.targetDeliveryTime ?? release,
          createdAt: invoice.createdAt,
          preparationMinutes: invoice.prepTimeMinutes ?? 20,
          routeMinutes: invoice.routeTimeMinutes ?? 15,
          cashierBufferMinutes: invoice.cashierBufferMinutes ?? 0,
          notes: invoice.address,
        ),
      ),
    );
  }
  return actions;
}

String _clock(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}';
}
