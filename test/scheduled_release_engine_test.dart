import 'package:almenupro/models/order.dart';
import 'package:almenupro/models/scheduled_order.dart';
import 'package:almenupro/services/scheduled_orders_controller.dart';
import 'package:almenupro/services/scheduled_release_engine.dart';
import 'package:almenupro/utils/order_channel_utils.dart';
import 'package:flutter_test/flutter_test.dart';

ScheduledOrder _delivery({
  required DateTime target,
  int prep = 20,
  int route = 15,
  int buffer = 0,
  String phone = '96550001122',
}) {
  return ScheduledOrder(
    id: 'd1',
    kind: ScheduledKind.delivery,
    customerName: 'نورة',
    phone: phone,
    targetAt: target,
    createdAt: target.subtract(const Duration(days: 1)),
    preparationMinutes: prep,
    routeMinutes: route,
    cashierBufferMinutes: buffer,
  );
}

void main() {
  test('print release time subtracts route, prep, and the cashier buffer', () {
    final target = DateTime.utc(2026, 10, 17, 18);
    final order = _delivery(target: target, prep: 20, route: 15, buffer: 10);
    expect(order.releaseAt, DateTime.utc(2026, 10, 17, 17, 15));
    expect(order.orderTypeWire, 'scheduled_delivery');
    expect(order.toJson()['status'], 'scheduled');
    expect(order.toJson()['orderType'], 'scheduled_delivery');
    final restored = ScheduledOrder.fromJson(order.toJson());
    expect(restored.cashierBufferMinutes, 10);
    expect(restored.releaseAt, order.releaseAt);
  });

  test('the hold stays scheduled until release time, then enters the kitchen', () {
    final target = DateTime.utc(2026, 10, 17, 18);
    final order = _delivery(target: target, phone: '1');
    final early = planScheduledRelease([order], DateTime.utc(2026, 10, 17, 16));
    expect(early.next.single.status, ScheduledHoldStatus.scheduled);
    expect(early.actions, isEmpty);

    final due = planScheduledRelease([order], order.releaseAt);
    expect(due.next.single.status, ScheduledHoldStatus.inKitchen);
    expect(due.actions.single.kind, ScheduledDeskActionKind.kitchenRelease);
  });

  test('table lock starts 30 minutes before a dine-in booking', () {
    final target = DateTime(2026, 10, 17, 20);
    final booking = ScheduledOrder(
      id: 't1',
      kind: ScheduledKind.dineIn,
      customerName: 'أحمد',
      phone: '96551111111',
      tableNumber: '4',
      targetAt: target,
      createdAt: target.subtract(const Duration(hours: 5)),
      preparationMinutes: 15,
    );
    expect(scheduledTableIsLocked([booking], '4', target.subtract(const Duration(minutes: 31))), isFalse);
    expect(scheduledTableIsLocked([booking], '4', target.subtract(const Duration(minutes: 30))), isTrue);
    expect(scheduledTableIsLocked([booking], '5', target.subtract(const Duration(minutes: 10))), isFalse);
  });

  test('whatsapp fires one hour before and the driver notice fires 30 minutes before', () {
    final target = DateTime.utc(2026, 10, 17, 18);
    final order = _delivery(target: target, prep: 10, route: 10);
    final reminder = planScheduledRelease([order], target.subtract(const Duration(hours: 1)));
    expect(reminder.actions.map((action) => action.kind), [ScheduledDeskActionKind.whatsappReminder]);

    final reminded = reminder.next.single;
    final driver = planScheduledRelease([reminded], target.subtract(const Duration(minutes: 30)));
    expect(driver.actions.map((action) => action.kind), [ScheduledDeskActionKind.driverNotice]);
    expect(driver.actions.single.order.reminderSentAt, isNotNull);

    final again = planScheduledRelease(driver.next, target.subtract(const Duration(minutes: 25)));
    expect(again.actions, isEmpty);
  });

  test('the cashier badge counts scheduled orders inside the next two hours', () {
    final now = DateTime(2026, 10, 17, 12);
    final soon = _delivery(target: now.add(const Duration(minutes: 40)));
    final later = _delivery(target: now.add(const Duration(hours: 3)));
    expect(upcomingScheduledCount([soon, later], now), 1);
  });

  test('a saved hold is released by the desk clock only once', () async {
    final store = MemoryScheduledOrdersStore();
    final desk = ScheduledOrdersController(store: store);
    final target = DateTime.utc(2026, 10, 17, 18);
    await desk.add(
      ScheduledOrder(
        id: 't1',
        kind: ScheduledKind.dineIn,
        customerName: 'أحمد',
        phone: '12',
        tableNumber: '4',
        targetAt: target,
        createdAt: target.subtract(const Duration(hours: 5)),
        preparationMinutes: 15,
      ),
    );
    desk.applyTick(target.subtract(const Duration(hours: 3)));
    expect(desk.orders.single.status, ScheduledHoldStatus.scheduled);
    desk.applyTick(target.subtract(const Duration(minutes: 15)));
    expect(desk.orders.single.status, ScheduledHoldStatus.inKitchen);
    expect(desk.drainActions().single.kind, ScheduledDeskActionKind.kitchenRelease);
    desk.applyTick(target.subtract(const Duration(minutes: 14)));
    expect(desk.drainActions(), isEmpty);
    expect(store.saved.single.status, ScheduledHoldStatus.inKitchen);
    desk.dispose();
  });

  test('the invoice stores scheduled_delivery and the calculated release time', () {
    final target = DateTime.utc(2026, 10, 17, 18);
    final release = target.subtract(const Duration(minutes: 35));
    final order = Order(
      id: 'o1',
      customerName: 'نورة',
      phone: '96550001122',
      address: 'حولي',
      items: const [],
      totalPrice: 4,
      orderType: OrderType.scheduledDelivery,
      status: OrderStatus.scheduled,
      createdAt: target.subtract(const Duration(hours: 2)),
      deliveryDate: target,
      targetDeliveryTime: target,
      prepTimeMinutes: 20,
      routeTimeMinutes: 15,
      cashierBufferMinutes: 0,
      autoReleaseTime: release,
    );

    final map = order.toMap();
    expect(map['status'], 'scheduled');
    expect(map['orderType'], 'scheduled_delivery');
    expect(map['prepTimeMinutes'], 20);
    expect(map['routeTimeMinutes'], 15);
    expect(map['autoReleaseTime'], release.toIso8601String());

    final restored = Order.fromMap('o1', map);
    expect(restored.status, OrderStatus.scheduled);
    expect(restored.orderType, OrderType.scheduledDelivery);
    expect(restored.prepTimeMinutes, 20);
    expect(restored.routeTimeMinutes, 15);
    expect(restored.resolvedAutoReleaseTime, release);
    expect(OrderStatus.fromString('in_kitchen'), OrderStatus.inKitchen);
  });

  test('scheduled invoices stay out of the live board until release time', () {
    final target = DateTime.utc(2026, 10, 17, 18);
    final release = target.subtract(const Duration(minutes: 35));
    final held = Order(
      id: 'held',
      customerName: 'نورة',
      phone: '96550001122',
      address: 'حولي',
      items: const [],
      totalPrice: 4,
      orderType: OrderType.scheduledDelivery,
      status: OrderStatus.scheduled,
      createdAt: target.subtract(const Duration(hours: 2)),
      targetDeliveryTime: target,
      prepTimeMinutes: 20,
      routeTimeMinutes: 15,
      autoReleaseTime: release,
    );
    final live = held.copyWith(status: OrderStatus.inKitchen);
    expect(isScheduledHoldOrder(held), isTrue);
    expect(withoutScheduledHolds([held, live]), [live]);
    expect(scheduledHoldOrders([held, live]).single.id, 'held');
    expect(
      dueScheduledInvoiceActions([held], const [], release).single.kind,
      ScheduledDeskActionKind.kitchenRelease,
    );
    expect(
      dueScheduledInvoiceActions(
        [held],
        [
          ScheduledOrder(
            id: 'held',
            kind: ScheduledKind.delivery,
            customerName: 'نورة',
            phone: '1',
            targetAt: target,
            createdAt: target,
          ),
        ],
        release,
      ),
      isEmpty,
    );
  });
}
