import 'dart:async';
import 'dart:html' as html;

import 'pos_receipt_document.dart';

/// Prints a full HTML thermal receipt on Flutter web.
///
/// Uses a hidden same-origin iframe or an in-page print host — never opens a
/// new browser tab (no `window.open`).
Future<void> printPosReceiptHtml(
  String htmlContent, {
  bool zeroClick = false,
}) async {
  final baseHtml = normalizePosReceiptDocument(htmlContent);
  if (baseHtml.trim().isEmpty) return;
  final selfPrintingHtml = withPosReceiptAutoPrintScript(baseHtml);

  final viaIframe = await _printViaHiddenIframe(
    selfPrintingHtml,
    sizedForThermal: zeroClick,
  );
  if (viaIframe) return;

  if (await _printViaInvisibleHost(baseHtml)) return;

  await _printViaInvisibleHost(selfPrintingHtml);
}

bool _isElectronShell() {
  try {
    return html.window.navigator.userAgent.toLowerCase().contains('electron');
  } catch (_) {
    return false;
  }
}

Future<bool> _printViaHiddenIframe(
  String documentHtml, {
  bool sizedForThermal = false,
}) async {
  final body = html.document.body;
  if (body == null) return false;

  final completer = Completer<bool>();
  final iframe = html.IFrameElement()
    ..setAttribute('aria-hidden', 'true')
    ..setAttribute('title', 'POS receipt print')
    ..style.cssText = sizedForThermal
        ? 'position:fixed;left:-10000px;top:0;width:80mm;height:200mm;'
            'border:0;opacity:0;pointer-events:none;'
        : 'position:fixed;right:0;bottom:0;width:0;height:0;border:0;'
            'opacity:0;pointer-events:none;visibility:hidden;';

  StreamSubscription<html.Event>? loadSub;
  Timer? safety;
  String? blobUrl;

  void finish(bool ok) {
    if (completer.isCompleted) return;
    safety?.cancel();
    unawaited(loadSub?.cancel() ?? Future<void>.value());
    try {
      iframe.remove();
    } catch (_) {}
    final url = blobUrl;
    if (url != null) {
      unawaited(
        Future<void>.delayed(const Duration(seconds: 90), () {
          html.Url.revokeObjectUrl(url);
        }),
      );
    }
    completer.complete(ok);
  }

  body.append(iframe);

  loadSub = iframe.onLoad.listen((_) async {
    await Future<void>.delayed(const Duration(milliseconds: 280));
    try {
      final dynamic frame = iframe;
      final dynamic win = frame.contentWindow;
      dynamic doc = frame.contentDocument;

      var bodyHtml = _readBodyHtml(doc);
      if (bodyHtml.isEmpty) {
        try {
          doc.open();
          doc.write(documentHtml);
          doc.close();
          await Future<void>.delayed(const Duration(milliseconds: 200));
          doc = frame.contentDocument;
          bodyHtml = _readBodyHtml(doc);
        } catch (_) {}
      }

      if (win == null || bodyHtml.isEmpty) {
        finish(false);
        return;
      }

      final electron = _isElectronShell();
      if (!electron) {
        try {
          win.print();
        } catch (_) {}
      } else {
        // Electron: receipt document includes a single guarded auto-print.
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      finish(true);
    } catch (_) {
      finish(false);
    }
  });

  safety = Timer(const Duration(seconds: 6), () => finish(false));

  try {
    iframe.srcdoc = documentHtml;
  } catch (_) {
    try {
      final blob = html.Blob([documentHtml], 'text/html;charset=utf-8');
      blobUrl = html.Url.createObjectUrlFromBlob(blob);
      iframe.src = blobUrl;
    } catch (_) {
      finish(false);
    }
  }

  return completer.future;
}

Future<bool> _printViaInvisibleHost(String documentHtml) async {
  final body = html.document.body;
  if (body == null) return false;

  html.Element? host;
  html.StyleElement? style;
  try {
    style = html.StyleElement()
      ..id = 'almenupro-thermal-print-style'
      ..text = '''
@media print {
  body * { visibility: hidden !important; }
  #almenupro-thermal-print-host,
  #almenupro-thermal-print-host * {
    visibility: visible !important;
  }
  #almenupro-thermal-print-host {
    position: absolute !important;
    left: 0 !important;
    top: 0 !important;
    width: 80mm !important;
    background: #fff !important;
  }
}
''';
    html.document.head?.append(style);

    host = html.DivElement()
      ..id = 'almenupro-thermal-print-host'
      ..style.cssText =
          'position:fixed;left:-10000px;top:0;width:80mm;background:#fff;';
    host.append(
      html.IFrameElement()
        ..style.cssText = 'width:80mm;min-height:120mm;border:0;'
        ..srcdoc = documentHtml,
    );
    body.append(host);

    await Future<void>.delayed(const Duration(milliseconds: 320));
    html.window.print();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return true;
  } catch (_) {
    return false;
  } finally {
    try {
      host?.remove();
    } catch (_) {}
    try {
      style?.remove();
    } catch (_) {}
  }
}

String _readBodyHtml(dynamic doc) {
  try {
    final value = doc?.body?.innerHTML ?? doc?.body?.innerHtml;
    if (value is String) return value.trim();
  } catch (_) {}
  return '';
}