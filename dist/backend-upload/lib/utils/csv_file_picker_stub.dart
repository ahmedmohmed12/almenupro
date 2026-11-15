/// Result of picking a delivery-zones import file from the browser.
class PickedImportFile {
  const PickedImportFile({
    required this.fileName,
    this.csvText,
    this.base64,
  });

  final String fileName;
  final String? csvText;
  final String? base64;

  bool get isExcel {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.xlsx') ||
        lower.endsWith('.xls') ||
        lower.endsWith('.xlsm');
  }
}

Future<PickedImportFile?> pickDeliveryZonesImportFile() async =>
    pickCsvFileContent();

/// Legacy alias — returns picked file descriptor (not raw CSV only).
Future<PickedImportFile?> pickCsvFileContent() async {
  return null;
}

void downloadCsvFile({required String filename, required String content}) {}
