import 'dart:typed_data';

Future<void> saveBytesToDownload(
  Uint8List bytes,
  String filename, {
  String mime = 'image/png',
}) async {
  // Desktop/mobile: clipboard/file picker not wired; no-op with clear error.
  throw UnsupportedError(
    'File download is supported on Flutter Web.',
  );
}

Future<void> openHtmlForPrint(String htmlSource) async {
  throw UnsupportedError('Print export is supported on Flutter Web.');
}
