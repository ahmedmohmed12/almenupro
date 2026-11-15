import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:qr_flutter/qr_flutter.dart';

import 'link_hub_qr_download_stub.dart'
    if (dart.library.html) 'link_hub_qr_download_web.dart';

Future<void> downloadLinkHubQrPng(
  String data, {
  required String filename,
}) async {
  final painter = QrPainter(
    data: data,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.M,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: ui.Color(0xFF6B1124),
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: ui.Color(0xFF1A1A1A),
    ),
  );
  final imageData =
      await painter.toImageData(1024, format: ui.ImageByteFormat.png);
  final bytes = imageData?.buffer.asUint8List();
  if (bytes == null) {
    throw StateError('QR render failed');
  }
  await downloadBytesAsFile(bytes, filename: filename);
}

Future<void> downloadBytesAsFile(
  Uint8List bytes, {
  required String filename,
  String mime = 'image/png',
}) {
  return saveBytesToDownload(bytes, filename, mime: mime);
}

Future<void> openReportPrintView(String htmlSource) {
  return openHtmlForPrint(htmlSource);
}
