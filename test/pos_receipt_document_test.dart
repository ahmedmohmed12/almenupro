import 'package:almenupro/services/pos_receipt_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeDocument wraps fragment with RTL Arabic shell', () {
    const frag = '<div>فاتورة</div>';
    final doc = normalizePosReceiptDocument(frag);
    expect(doc.toLowerCase(), contains('<html'));
    expect(doc, contains('dir="rtl"'));
    expect(doc, contains('lang="ar"'));
    expect(doc, contains(frag));
  });

  test('withAutoPrintScript injects guarded script once', () {
    const doc = '<html><body></body></html>';
    final once = withPosReceiptAutoPrintScript(doc);
    final twice = withPosReceiptAutoPrintScript(once);
    expect(once, contains('data-almenupro-autoprint'));
    expect(once, contains('window.print'));
    expect(once, contains('__almenuproReceiptPrintFired'));
    expect(twice, same(once));
  });
}