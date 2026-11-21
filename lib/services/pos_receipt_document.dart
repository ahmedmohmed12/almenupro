/// Pure-Dart helpers for thermal receipt HTML documents (testable on VM).
String normalizePosReceiptDocument(String raw) {
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

String withPosReceiptAutoPrintScript(String htmlContent) {
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
    setTimeout(triggerPrint, 180);
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