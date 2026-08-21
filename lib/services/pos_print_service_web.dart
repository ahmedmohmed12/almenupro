import 'dart:async';
import 'dart:html' as html;

/// Prints a full HTML thermal receipt on Flutter web.
///
/// Prefer a hidden same-origin iframe (`srcdoc` / blob URL) so markup is
/// actually painted before `window.print()`. Avoids blank `about:blank`
/// popups that browsers often leave empty when `document.write` is blocked.
Future<void> printPosReceiptHtml(String htmlContent) async {
  final baseHtml = _normalizeDocument(htmlContent);
  if (baseHtml.trim().isEmpty) return;

  final viaIframe = await _printViaHiddenIframe(baseHtml);
  if (viaIframe) return;

  // Popup path includes an in-document auto-print script because opener
  // access to the new window is often blocked (COOP / noopener).
  await _printViaBlobPopup(_withAutoPrintScript(baseHtml));
}

Future<bool> _printViaHiddenIframe(String documentHtml) async {
  final body = html.document.body;
  if (body == null) return false;

  final completer = Completer<bool>();
  final iframe = html.IFrameElement()
    ..setAttribute('aria-hidden', 'true')
    ..setAttribute('title', 'POS receipt print')
    ..style.cssText =
        'position:fixed;right:0;bottom:0;width:0;height:0;border:0;'
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
    await Future<void>.delayed(const Duration(milliseconds: 300));
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
      try {
        win.focus();
      } catch (_) {}
      win.print();
      await Future<void>.delayed(const Duration(milliseconds: 800));
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

String _readBodyHtml(dynamic doc) {
  try {
    final value = doc?.body?.innerHTML ?? doc?.body?.innerHtml;
    if (value is String) return value.trim();
  } catch (_) {}
  return '';
}

Future<void> _printViaBlobPopup(String documentHtml) async {
  final blob = html.Blob([documentHtml], 'text/html;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);

  html.window.open(url, '_blank');

  unawaited(
    Future<void>.delayed(const Duration(seconds: 90), () {
      html.Url.revokeObjectUrl(url);
    }),
  );

  await Future<void>.delayed(const Duration(milliseconds: 700));
}

String _normalizeDocument(String raw) {
  var htmlContent = raw.trim();
  if (htmlContent.isEmpty) return '';

  if (!htmlContent.toLowerCase().contains('<html')) {
    htmlContent = '''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Receipt</title>
</head>
<body>$htmlContent</body>
</html>''';
  }
  return htmlContent;
}

String _withAutoPrintScript(String htmlContent) {
  const marker = 'data-almenupro-autoprint';
  if (htmlContent.contains(marker)) return htmlContent;

  const autoPrintScript = '''
<script $marker="1">
(function () {
  function triggerPrint() {
    try {
      window.focus();
      window.print();
    } catch (e) {}
  }
  function schedule() {
    setTimeout(triggerPrint, 200);
  }
  if (document.readyState === 'complete') schedule();
  else window.addEventListener('load', schedule);
})();
</script>
''';

  final lower = htmlContent.toLowerCase();
  final bodyClose = lower.lastIndexOf('</body>');
  if (bodyClose != -1) {
    return htmlContent.substring(0, bodyClose) +
        autoPrintScript +
        htmlContent.substring(bodyClose);
  }
  return '$htmlContent$autoPrintScript';
}
