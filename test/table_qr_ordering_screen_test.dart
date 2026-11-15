import 'package:almenupro/providers/cart_provider.dart';
import 'package:almenupro/providers/customer_session_provider.dart';
import 'package:almenupro/providers/locale_provider.dart';
import 'package:almenupro/providers/order_type_provider.dart';
import 'package:almenupro/screens/table_qr_ordering_screen.dart';
import 'package:almenupro/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Table QR ordering page loads demo catalog and binds table', (
    tester,
  ) async {
    final session = CustomerSessionProvider();
    final cart = CartProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: cart),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ChangeNotifierProvider(create: (_) => OrderTypeProvider()),
          ChangeNotifierProvider.value(value: session),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const TableQrOrderingScreen(
            branchId: '101',
            tableId: '5',
            restaurantId: '101',
            tableName: 'طاولة 05',
            zone: 'الصالة الرئيسية',
            restaurantName: 'AlMenuPro Demo',
            useDemoCatalog: true,
          ),
        ),
      ),
    );

    // Post-frame bootstrap + catalog apply (avoid pumpAndSettle: loading spinner).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('طاولة'), findsWidgets);
    expect(find.text('نداء الويتر'), findsOneWidget);
    expect(find.text('مقبلات'), findsWidgets);
    expect(session.dineInTableId, '5');
    expect(session.isQrDineIn, isTrue);

    await tester.tap(find.text('حمص بالطحينة').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('أضف'), findsWidgets);
  });
}
