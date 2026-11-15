import 'dart:typed_data';

Future<void> saveBytesToDownload(Uint8List bytes, String filename) async {
  // Desktop/mobile: clipboard/file picker not wired; no-op with clear error.
  throw UnsupportedError(
    'QR file download is supported on Flutter Web. Use Copy Link on desktop.',
  );
}
