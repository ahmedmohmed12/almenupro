import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:almenupro/models/dining_table.dart';
import 'package:almenupro/models/menu_item.dart';
import 'package:almenupro/models/order.dart';
import 'package:almenupro/services/incoming_order_auto_accept_service.dart';
import 'package:almenupro/services/pos_print_helper.dart';
import 'package:almenupro/theme/app_theme.dart';
import 'package:almenupro/utils/order_channel_utils.dart';
import 'package:almenupro/utils/pos_receipt_html.dart';

void main() {
  testWidgets('Almenupro theme loads', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: Text('Almenupro')),
      ),
    );

    expect(find.text('Almenupro'), findsOneWidget);
  });

  test('POS orders start current without incoming-order alert', () {
    final order = Order.fromMap('pos-1', {
      'customerName': 'عميل الكاشير',
      'items': <Map<String, dynamic>>[],
      'totalPrice': 12.5,
      'orderType': 'delivery',
      'status': 'confirmed',
      'createdAt': DateTime.now().toIso8601String(),
      'orderSource': 'talabat',
      'createdFromPos': true,
    });

    expect(order.createdFromPos, isTrue);
    expect(order.isNewForAdmin, isFalse);
    expect(order.isCurrentForAdmin, isTrue);
    expect(isPendingOnlineMenuOrder(order), isFalse);
    expect(order.isCurrentForCashier, isTrue);
    expect(isCashierMenuOrder(order), isTrue);
    expect(
      order.copyWith(status: OrderStatus.delivered).status.isArchivedForAdmin,
      isTrue,
    );
  });

  test('Cashier helper includes POS source orders', () {
    final order = Order.fromMap('pos-2', {
      'customerName': 'عميل الكاشير',
      'items': <Map<String, dynamic>>[],
      'totalPrice': 12.5,
      'orderType': 'delivery',
      'status': 'confirmed',
      'createdAt': DateTime.now().toIso8601String(),
      'orderSource': 'pos',
      'createdFromPos': false,
    });

    expect(order.createdFromPos, isFalse);
    expect(isOnlineMenuOrder(order), isFalse);
    expect(isCashierMenuOrder(order), isTrue);
  });

  test('External platform orders enter the pending online alert pipeline', () {
    final order = Order.fromMap('external-1', {
      'customerName': 'External customer',
      'items': <Map<String, dynamic>>[
        {
          'name': 'Meal',
          'unitPrice': 2.5,
          'quantity': 1,
          'selectedOptions': <Map<String, dynamic>>[],
        },
      ],
      'totalPrice': 2.5,
      'orderType': 'delivery',
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
      'orderSource': 'talabat',
      'externalOrderId': 'TB-TEST-1',
      'createdFromPos': false,
    });

    expect(isOnlineMenuOrder(order), isTrue);
    expect(isPendingOnlineMenuOrder(order), isTrue);
    expect(order.isNewForAdmin, isTrue);
    expect(order.externalOrderId, 'TB-TEST-1');
  });

  test(
    'Incoming kitchen print is blocked without an open cashier shift',
    () async {
      final printed = await PosPrintHelper.printIncomingAcceptance(
        order: PosPrintHelper.buildTestOrder(),
        kind: PosReceiptKind.kitchen,
      );

      expect(printed, isFalse);
    },
  );

  test('No-shift order stays pending and publishes a POS warning', () {
    const orderId = String.fromEnvironment(
      'NO_SHIFT_ORDER_ID',
      defaultValue: 'MOCK-NOSHIFT-TEST',
    );
    final order = Order.fromMap(orderId, {
      'customerName': 'No-shift customer',
      'items': <Map<String, dynamic>>[
        {
          'name': 'Meal',
          'unitPrice': 2.5,
          'quantity': 1,
          'selectedOptions': <Map<String, dynamic>>[],
        },
      ],
      'totalPrice': 2.5,
      'orderType': 'delivery',
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
      'orderSource': 'talabat',
      'externalOrderId': orderId,
      'createdFromPos': false,
    });
    final service = IncomingOrderAutoAcceptService.instance;
    service.syncPendingIds({});
    service.shiftReadinessWarning.value = null;

    service.trackNewOrder(order);

    expect(order.status, OrderStatus.pending);
    expect(service.shiftReadinessWarning.value, orderId);
    expect(service.remainingSeconds(orderId), isNotNull);
    service.syncPendingIds({});
  });

  test('Closed hall table bills are flagged for صالة tab and channel', () {
    final order = Order.fromMap('table-1', {
      'customerName': 'طاولة 5',
      'items': <Map<String, dynamic>>[],
      'totalPrice': 8.25,
      'orderType': 'dineIn',
      'status': 'delivered',
      'createdAt': DateTime.now().toIso8601String(),
      'orderSource': 'pos-dine-in',
      'createdFromPos': true,
      'tableId': 'tbl_5',
      'shiftId': 'shift_1',
    });

    expect(isHallTableOrder(order), isTrue);
    expect(isClosedHallTableOrder(order), isTrue);
    expect(isPendingOnlineMenuOrder(order), isFalse);
  });

  test(
    'POS-only menu items stay available for cashier but hidden from website',
    () {
      final item = MenuItem.fromJson({
        'id': 9,
        'name': 'صنف داخلي',
        'price': 1.5,
        'isAvailable': true,
        'showOnWebsite': false,
      });

      expect(item.isAvailable, isTrue);
      expect(item.showOnWebsite, isFalse);
    },
  );

  test('Occupied table exposes order number, elapsed time, and amount', () {
    final table = DiningTable.fromJson({
      'id': 'table-5',
      'number': '5',
      'status': 'occupied',
      'activeSession': {
        'id': 'session-5',
        'openedAt': DateTime.now()
            .subtract(const Duration(minutes: 17))
            .toUtc()
            .toIso8601String(),
        'currentOrderNumber': '12345',
        'cartItems': [
          {'name': 'صنف 1', 'quantity': 2, 'unitPrice': 1.25},
          {'name': 'صنف 2', 'quantity': 1, 'lineTotal': 3.5},
        ],
      },
    });

    expect(table.currentOrderNumber, '12345');
    expect(table.sessionAmount, 6.0);
    expect(table.elapsedLabel, contains('17'));
  });

  test('Bill request locks table and exposes tip, total, and payment', () {
    final table = DiningTable.fromJson({
      'id': 'table-7',
      'number': '7',
      'status': 'awaiting_check',
      'activeSession': {
        'id': 'session-7',
        'checkRequested': true,
        'tipAmount': 1.0,
        'paymentMethod': 'knet',
        'billTotal': 7.0,
        'cartItems': [
          {'name': 'Meal', 'quantity': 2, 'unitPrice': 3.0},
        ],
      },
    });

    expect(table.isAwaitingCheck, isTrue);
    expect(table.requestedTip, 1.0);
    expect(table.requestedBillTotal, 7.0);
    expect(table.requestedPaymentMethod, 'knet');
  });

  test('Kitchen table ticket highlights table number and payment', () {
    final order = Order.fromMap('kitchen-1', {
      'customerName': 'طاولة 5',
      'phone': '00000000',
      'address': 'طاولة 5 — الصالة الرئيسية',
      'items': [
        {
          'menuItemId': '1',
          'name': 'دجاج حنيذ',
          'quantity': 1,
          'unitPrice': 3.5,
        },
      ],
      'totalPrice': 3.5,
      'orderType': 'dineIn',
      'status': 'preparing',
      'createdAt': DateTime.now().toIso8601String(),
      'paymentMethod': 'كاش',
      'tableId': 'tbl_5',
      'tableNumber': '5',
      'orderSource': 'pos-dine-in',
      'store_name': 'طلبات دار السعد',
    });

    final html = PosReceiptHtml.build(
      order: order,
      restaurantName: 'Nour Alyaman',
      kind: PosReceiptKind.kitchen,
    );

    expect(html.contains('طاولة 5'), isTrue);
    expect(html.contains('كاش'), isTrue);
    expect(html.contains('رقم الطاولة'), isTrue);
    expect(html.contains('طريقة الدفع'), isTrue);
    expect(html.contains('table-value'), isTrue);
    expect(html.contains('payment-value'), isTrue);
    expect(order.storeName, 'طلبات دار السعد');
    expect(html.contains('طلبات دار السعد'), isFalse);
    expect(html.contains('store_name'), isFalse);
  });
}
