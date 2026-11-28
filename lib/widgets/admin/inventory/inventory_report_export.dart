import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// CSV helper for Foodics-style report export (web/admin clipboard).
class InventoryReportExport {
  static String toCsv(List<Map<String, dynamic>> rows, List<String> columns) {
    final buffer = StringBuffer();
    buffer.writeln(columns.join(','));
    for (final row in rows) {
      final cells = columns.map((col) {
        final raw = row[col];
        final text = raw == null ? '' : '$raw';
        if (text.contains(',') || text.contains('"') || text.contains('\n')) {
          return '"${text.replaceAll('"', '""')}"';
        }
        return text;
      });
      buffer.writeln(cells.join(','));
    }
    return buffer.toString();
  }

  static Future<void> copyToClipboard(BuildContext context, String csv, String label) async {
    await Clipboard.setData(ClipboardData(text: csv));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم نسخ $label إلى الحافظة (CSV)')),
    );
  }
}