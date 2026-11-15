import 'dart:html' as html;
import 'dart:typed_data';

Future<void> saveBytesToDownload(
  Uint8List bytes,
  String filename, {
  String mime = 'image/png',
}) async {
  final blob = html.Blob([bytes], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

Future<void> openHtmlForPrint(String htmlSource) async {
  final blob = html.Blob([htmlSource], 'text/html');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
}
