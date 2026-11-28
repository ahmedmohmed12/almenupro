import 'package:almenupro/widgets/admin/inventory/inventory_report_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CSV escapes commas and quotes', () {
    final csv = InventoryReportExport.toCsv(
      [
        {'name': 'طماطم, طازجة', 'qty': 2, 'note': 'قال "نعم"'},
      ],
      const ['name', 'qty', 'note'],
    );
    expect(csv.contains('"طماطم, طازجة"'), isTrue);
    expect(csv.contains('""نعم""'), isTrue);
  });
}