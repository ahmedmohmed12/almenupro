import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'csv_file_picker_stub.dart' show PickedImportFile;

export 'csv_file_picker_stub.dart' show PickedImportFile;

/// Triggers a CSV file download in the browser.
void downloadCsvFile({required String filename, required String content}) {
  final bytes = html.Blob([content], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(bytes);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

/// Opens a file picker for CSV or Excel delivery-zone imports.
Future<PickedImportFile?> pickDeliveryZonesImportFile() async {
  final input = html.FileUploadInputElement()
    ..accept =
        '.csv,.txt,.xlsx,.xls,.xlsm,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel'
    ..multiple = false;

  input.click();
  await input.onChange.first;
  final file = input.files?.first;
  if (file == null) return null;

  final fileName = file.name;
  final lower = fileName.toLowerCase();
  final isExcel =
      lower.endsWith('.xlsx') || lower.endsWith('.xls') || lower.endsWith('.xlsm');

  if (isExcel) {
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoad.first;
    final buffer = reader.result;
    if (buffer is! ByteBuffer) return null;
    final bytes = Uint8List.view(buffer);
    return PickedImportFile(
      fileName: fileName,
      base64: base64Encode(bytes),
    );
  }

  final reader = html.FileReader();
  reader.readAsText(file, 'utf-8');
  await reader.onLoad.first;
  final text = reader.result?.toString();
  if (text == null || text.trim().isEmpty) return null;

  return PickedImportFile(
    fileName: fileName,
    csvText: text,
  );
}

/// Backward-compatible alias.
Future<PickedImportFile?> pickCsvFileContent() => pickDeliveryZonesImportFile();
