import 'package:almenupro/models/customer.dart';
import 'package:almenupro/models/order.dart';
import 'package:almenupro/services/whatsapp_broadcast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('template replaces placeholders for one client', () {
    const recipient = BroadcastRecipient(
      id: '1',
      name: 'سارة',
      phone: '96550001122',
      platform: BroadcastPlatform.talabat,
      restaurantName: 'دار السعد',
    );
    final message = renderBroadcastTemplate(
      defaultBroadcastTemplate,
      recipient,
    );
    expect(message.contains('{name}'), isFalse);
    expect(message, contains('سارة'));
    expect(message, contains('دار السعد'));
    expect(message, contains('طلبات'));
    expect(message, contains('Menu Engineering'));
  });

  test('Kuwait local numbers gain 965 and short numbers are rejected', () {
    expect(whatsAppBroadcastPhone('5000 1122'), '96550001122');
    expect(whatsAppBroadcastPhone('12'), isNull);
  });

  test('platform filter and master selection stay on the visible rows', () {
    final controller = WhatsappBroadcastController(
      audience: const [
        BroadcastRecipient(
          id: 'a',
          name: 'طلبات أ',
          phone: '96551111111',
          platform: BroadcastPlatform.talabat,
          restaurantName: 'دار السعد',
        ),
        BroadcastRecipient(
          id: 'b',
          name: 'جاهز ب',
          phone: '96552222222',
          platform: BroadcastPlatform.jahez,
          restaurantName: 'دار السعد',
        ),
      ],
    );
    controller.setPlatform(BroadcastPlatform.talabat);
    controller.selectAllVisible();
    expect(controller.targets.map((row) => row.id), ['a']);
    controller.invertVisible();
    expect(controller.targets, isEmpty);
    controller.setQuery('جاهز');
    controller.setPlatform(BroadcastPlatform.all);
    controller.selectAllVisible();
    expect(controller.targets.map((row) => row.id), ['b']);
  });

  test('invalid phones are skipped and logged', () async {
    final controller = WhatsappBroadcastController(
      audience: const [
        BroadcastRecipient(
          id: 'bad',
          name: 'بدون رقم',
          phone: '12',
          platform: BroadcastPlatform.direct,
          restaurantName: 'AlMenuPro',
        ),
      ],
    );
    controller.selectAllVisible();
    await controller.run((recipient, message) async => true);
    expect(controller.logs.single.status, BroadcastLogStatus.skipped);
    expect(controller.runState, BroadcastRunState.done);
  });

  test('audience uses the latest platform for a shared phone', () {
    final audience = buildBroadcastAudience(
      customers: [
        Customer(
          id: 'c1',
          phone: '96553333333',
          customerName: 'نورة',
          formattedAddress: '',
        ),
      ],
      orders: [
        Order(
          id: 'old',
          customerName: 'نورة',
          phone: '96553333333',
          address: '',
          items: const [],
          totalPrice: 1,
          orderType: OrderType.delivery,
          status: OrderStatus.confirmed,
          createdAt: DateTime.utc(2026, 1, 1),
          orderSource: 'jahez',
        ),
        Order(
          id: 'new',
          customerName: 'نورة',
          phone: '96553333333',
          address: '',
          items: const [],
          totalPrice: 2,
          orderType: OrderType.delivery,
          status: OrderStatus.confirmed,
          createdAt: DateTime.utc(2026, 6, 1),
          orderSource: 'talabat',
        ),
      ],
      restaurantName: 'دار السعد',
    );
    expect(audience.single.platform, BroadcastPlatform.talabat);
    expect(audience.single.restaurantName, 'دار السعد');
    expect(audience.single.orderTimes, hasLength(2));
  });

  test('date range keeps customers who ordered inside the window', () {
    final audience = buildBroadcastAudience(
      customers: [
        Customer(
          id: 'c1',
          phone: '96553333333',
          customerName: 'نورة',
          formattedAddress: '',
        ),
        Customer(
          id: 'c2',
          phone: '96554444444',
          customerName: 'بلا طلب',
          formattedAddress: '',
        ),
      ],
      orders: [
        Order(
          id: 'jan',
          customerName: 'نورة',
          phone: '96553333333',
          address: '',
          items: const [],
          totalPrice: 1,
          orderType: OrderType.delivery,
          status: OrderStatus.confirmed,
          createdAt: DateTime.utc(2026, 1, 15, 12),
          orderSource: 'talabat',
        ),
      ],
      restaurantName: 'دار السعد',
    );
    final controller = WhatsappBroadcastController(audience: audience);
    expect(controller.visible, hasLength(2));

    controller.setDateRange(
      DateTime.utc(2026, 1, 15, 12),
      DateTime.utc(2026, 1, 15, 12),
    );
    expect(controller.visible.map((row) => row.id), ['c1']);

    controller.setDateRange(
      DateTime.utc(2026, 3, 1),
      DateTime.utc(2026, 3, 31),
    );
    expect(controller.visible, isEmpty);

    controller.clearDateRange();
    expect(controller.visible, hasLength(2));
  });

  test(
    'range presets cover today, yesterday, the last 7 days, and this month',
    () {
      final now = DateTime(2026, 10, 16, 15, 30);
      final today = broadcastPresetRange(BroadcastRangePreset.today, now);
      expect(today.from, DateTime(2026, 10, 16));
      expect(today.to, broadcastEndOfDay(now));

      final yesterday = broadcastPresetRange(
        BroadcastRangePreset.yesterday,
        now,
      );
      expect(yesterday.from, DateTime(2026, 10, 15));

      final week = broadcastPresetRange(BroadcastRangePreset.last7Days, now);
      expect(week.from, DateTime(2026, 10, 10));
      expect(week.to, broadcastEndOfDay(now));

      final month = broadcastPresetRange(BroadcastRangePreset.thisMonth, now);
      expect(month.from, DateTime(2026, 10, 1));
      expect(month.to, broadcastEndOfDay(DateTime(2026, 10, 31)));

      final controller = WhatsappBroadcastController();
      controller.applyDatePreset(BroadcastRangePreset.today, now: now);
      expect(controller.activePreset, BroadcastRangePreset.today);
      expect(controller.rangeFrom, today.from);
      controller.clearDateRange();
      expect(controller.rangeFrom, isNull);
      expect(controller.activePreset, isNull);
    },
  );
}
