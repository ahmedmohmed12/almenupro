import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almenupro/models/platform_item_mapping.dart';
import 'package:almenupro/widgets/admin/admin_platform_menu_mapping_panel.dart';

void main() {
  test('platform mapping model supports option hierarchy', () {
    final mapping = PlatformItemMapping.fromMap({
      'id': 'mapping-1',
      'pos_item_id': '17',
      'platform_name': 'talabat',
      'platform_item_id': 'T-17-L',
      'platform_item_name': 'Chicken Majboos Large',
      'entity_type': 'variant',
      'parent_mapping_id': 'mapping-parent',
      'pos_option_id': 'large',
    });

    expect(mapping.posItemId, '17');
    expect(mapping.entityType, 'variant');
    expect(mapping.parentMappingId, 'mapping-parent');
    expect(mapping.posOptionId, 'large');
    expect(mapping.toMap()['platform_item_id'], 'T-17-L');
  });

  testWidgets('mapping panel protects missing restaurant scope', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AdminPlatformMenuMappingPanel(canManage: false)),
      ),
    );

    expect(find.textContaining('اختر مطعمًا'), findsOneWidget);
  });
}
