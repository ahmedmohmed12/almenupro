import 'dart:async';
import 'dart:html' as html;

void printPosReceiptHtml(String htmlContent) {
  final popup = html.window.open('about:blank', '_blank');
  if (popup == null) return;

  final dynamic win = popup;
  win.document.open();
  win.document.write(htmlContent);
  win.document.close();
  win.focus();

  // Allow layout/styles to settle before invoking the thermal print dialog.
  unawaited(
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      try {
        win.print();
      } catch (_) {
        // Popup may have been blocked or closed.
      }
    }),
  );
}
