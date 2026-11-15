import 'package:almenupro/models/order.dart';
import 'package:almenupro/services/admin_auth_service.dart';
import 'package:almenupro/services/smart_whatsapp_hub.dart';
import 'package:almenupro/widgets/admin/smart_whatsapp_hub_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Order _order({
  required String id,
  required OrderStatus status,
  required DateTime createdAt,
  String phone = '50001122',
  String? paymentMethod,
  String? deliveryStatus,
  DateTime? deliveredAt,
  bool isRated = false,
  OrderType orderType = OrderType.delivery,
}) {
  return Order(
    id: id,
    customerName: 'نورة',
    phone: phone,
    address: '',
    items: const [],
    totalPrice: 3,
    orderType: orderType,
    status: status,
    createdAt: createdAt,
    invoiceNumber: id,
    paymentMethod: paymentMethod,
    deliveryStatus: deliveryStatus,
    isRated: isRated,
    statusTimeline: OrderStatusTimeline(deliveredAt: deliveredAt),
  );
}

void main() {
  final now = DateTime.utc(2026, 10, 16, 12);

  test('welcome and dispatch queues follow the order stage', () {
    final tasks = buildWhatsappTasks(
      orders: [
        _order(id: 'new', status: OrderStatus.pending, createdAt: now.subtract(const Duration(minutes: 10))),
        _order(
          id: 'road',
          status: OrderStatus.preparing,
          createdAt: now.subtract(const Duration(minutes: 30)),
          phone: '50002233',
        ),
      ],
      restaurantName: 'دار السعد',
      now: now,
    );
    expect(tasks.where((task) => task.stage == WhatsappStage.welcome).map((task) => task.orderId), ['new']);
    expect(tasks.where((task) => task.stage == WhatsappStage.dispatch).map((task) => task.orderId), ['road']);
  });

  test('review queue waits 2 hours and drops cancelled, refunded, and late orders', () {
    final tasks = buildWhatsappTasks(
      orders: [
        _order(
          id: 'ready',
          status: OrderStatus.delivered,
          createdAt: now.subtract(const Duration(hours: 4)),
          deliveredAt: now.subtract(const Duration(hours: 3)),
          phone: '50003344',
        ),
        _order(
          id: 'too-soon',
          status: OrderStatus.delivered,
          createdAt: now.subtract(const Duration(minutes: 90)),
          deliveredAt: now.subtract(const Duration(minutes: 30)),
          phone: '50004455',
        ),
        _order(
          id: 'cancelled',
          status: OrderStatus.cancelled,
          createdAt: now.subtract(const Duration(hours: 5)),
          phone: '50005566',
        ),
        _order(
          id: 'refunded',
          status: OrderStatus.delivered,
          createdAt: now.subtract(const Duration(hours: 5)),
          deliveredAt: now.subtract(const Duration(hours: 4)),
          paymentMethod: 'refunded',
          phone: '50006677',
        ),
        _order(
          id: 'late',
          status: OrderStatus.delivered,
          createdAt: now.subtract(const Duration(hours: 5)),
          deliveredAt: now.subtract(const Duration(hours: 3)),
          deliveryStatus: 'delayed',
          phone: '50007788',
        ),
      ],
      restaurantName: 'دار السعد',
      now: now,
    );
    final reviews = tasks.where((task) => task.stage == WhatsappStage.review).map((task) => task.orderId);
    expect(reviews, ['ready']);
  });

  test('retention queue keeps customers silent for more than 3 days', () {
    final tasks = buildWhatsappTasks(
      orders: [
        _order(
          id: 'old',
          status: OrderStatus.delivered,
          createdAt: now.subtract(const Duration(days: 4)),
          deliveredAt: now.subtract(const Duration(days: 4)),
          phone: '50008899',
        ),
        _order(
          id: 'fresh',
          status: OrderStatus.delivered,
          createdAt: now.subtract(const Duration(hours: 5)),
          deliveredAt: now.subtract(const Duration(hours: 4)),
          phone: '50009900',
        ),
      ],
      restaurantName: 'دار السعد',
      now: now,
    );
    expect(
      tasks.where((task) => task.stage == WhatsappStage.retention).map((task) => task.orderId),
      ['old'],
    );
  });

  test('template preview fills the sample customer', () {
    final message = renderWhatsappStage(
      template: defaultWhatsappStageTemplates[WhatsappStage.review]!,
      name: 'أحمد',
      restaurantName: 'دار السعد',
      orderId: '1042',
      ratingLink: 'https://u-menus.com/order/1042/rate',
      discountCode: 'ALMENU10',
    );
    expect(message.contains('{name}'), isFalse);
    expect(message, contains('أحمد'));
    expect(message, contains('1042'));
    expect(message, contains('https://u-menus.com/order/1042/rate'));
  });

  test('sent keys are remembered so a task is not offered twice', () async {
    final store = MemoryWhatsappHubStore();
    final hub = SmartWhatsappHubController(store: store);
    final order = _order(
      id: 'new',
      status: OrderStatus.pending,
      createdAt: now.subtract(const Duration(minutes: 5)),
    );
    await hub.load([order], restaurantName: 'دار السعد', now: now);
    final task = hub.tasksFor(WhatsappStage.welcome).single;
    await hub.markSent(task);
    expect(hub.isSent(task), isTrue);
    expect(hub.pendingCount(WhatsappStage.welcome), 0);
    expect(store.sent, contains(task.sentKey));
    hub.dispose();
  });

  testWidgets('queue tab renders a data table for each stage', (tester) async {
    SharedPreferences.setMockInitialValues({
      'admin_auth_session':
          '{"token":"t","role":"restaurant_admin","restaurantName":"دار السعد"}',
    });
    await AdminAuthService.instance.initialize();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SmartWhatsappHubPage())),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PaginatedDataTable), findsOneWidget);
    expect(find.text('الاسم'), findsOneWidget);
    expect(find.text('رقم الهاتف'), findsOneWidget);
    expect(find.text('رقم الطلب'), findsOneWidget);
    expect(find.text('حالة الإرسال'), findsOneWidget);
    expect(find.text('الإجراء'), findsOneWidget);

    await tester.tap(find.text('طابور التوصيل'));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد مهام في هذا الطابور.'), findsOneWidget);
  });

  testWidgets('queue table stays laid out on a narrow POS width', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SmartWhatsappHubPage())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PaginatedDataTable), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
