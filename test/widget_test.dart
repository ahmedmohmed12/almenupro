import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:almenupro/theme/app_theme.dart';

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
}
