import 'package:intl/intl.dart';

import '../models/order.dart';

enum PosReceiptKind { kitchen, customer }

enum PosReceiptPaperWidth { mm80, mm58 }

class PosReceiptHtml {
  static String build({
    required Order order,
    required String restaurantName,
    required PosReceiptKind kind,
    String? restaurantPhone,
    String? restaurantAddress,
    PosReceiptPaperWidth paperWidth = PosReceiptPaperWidth.mm80,
  }) {
    final time =
        DateFormat('yyyy-MM-dd HH:mm').format(order.createdAt.toLocal());
    final orderId = order.invoiceNumber ?? order.id;
    final isKitchen = kind == PosReceiptKind.kitchen;
    final title = isKitchen ? 'تذكرة المطبخ' : 'فاتورة العميل';
    final paperClass =
        paperWidth == PosReceiptPaperWidth.mm58 ? 'paper-58' : 'paper-80';
    final bodyClass =
        '$paperClass ${isKitchen ? 'kitchen-ticket' : 'customer-receipt'}';

    final rows = order.items.map((item) {
      final addons = item.selectedOptions
          .map(
            (option) =>
                '<div class="addon">+ ${_escape(option.group)}: ${_escape(option.name)}</div>',
          )
          .join('');
      final notes = item.specialNotes?.trim().isNotEmpty ?? false
          ? '<div class="note">⚠ ${_escape(item.specialNotes!.trim())}</div>'
          : '';

      if (isKitchen) {
        return '''
        <div class="kitchen-item">
          <div class="kitchen-qty">${item.quantity}x</div>
          <div class="kitchen-details">
            <div class="kitchen-name">${_escape(item.name)}</div>
            $addons$notes
          </div>
        </div>''';
      }

      return '''
        <tr>
          <td class="qty">${item.quantity}x</td>
          <td class="item-name">${_escape(item.name)}$addons$notes</td>
          <td class="price">${item.lineTotal.toStringAsFixed(3)}</td>
        </tr>''';
    }).join();

    final subtotal = order.subtotal ?? order.totalPrice;
    final deliveryFee = order.deliveryFee ?? 0;
    final phoneLine = restaurantPhone?.trim().isNotEmpty ?? false
        ? '<div class="meta-row">📞 ${_escape(restaurantPhone!.trim())}</div>'
        : '';
    final addressLine = restaurantAddress?.trim().isNotEmpty ?? false
        ? '<div class="meta-row">📍 ${_escape(restaurantAddress!.trim())}</div>'
        : '';

    final itemsBlock = isKitchen
        ? '<div class="kitchen-items">$rows</div>'
        : '''
  <table class="items-table">
    <thead>
      <tr>
        <th>كم</th>
        <th>الصنف</th>
        <th class="price-col">د.ك</th>
      </tr>
    </thead>
    <tbody>$rows</tbody>
  </table>''';

    final totalsBlock = isKitchen
        ? ''
        : '''
  <div class="totals">
    <div class="total-row"><span>المجموع الفرعي</span><span>${subtotal.toStringAsFixed(3)}</span></div>
    <div class="total-row"><span>التوصيل</span><span>${deliveryFee.toStringAsFixed(3)}</span></div>
    <div class="total-row grand"><span>الإجمالي</span><span>${order.totalPrice.toStringAsFixed(3)} د.ك</span></div>
  </div>''';

    return '''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$title — ${_escape(restaurantName)}</title>
  <style>
    $_thermalCss
  </style>
</head>
<body class="$bodyClass">
  <div id="receipt-root" class="receipt-root">
    <div class="receipt-header">
      <div class="brand">${_escape(restaurantName)}</div>
      $phoneLine
      $addressLine
    </div>
    <div class="divider dashed"></div>
    <div class="receipt-title">$title</div>
    <div class="order-meta">
      <div class="meta-row"><strong>طلب #</strong> ${_escape(orderId)}</div>
      <div class="meta-row"><strong>الوقت</strong> $time</div>
      <div class="meta-row"><strong>العميل</strong> ${_escape(order.customerName)}</div>
      <div class="meta-row"><strong>هاتف</strong> ${_escape(order.phone)}</div>
      ${isKitchen ? '' : '<div class="meta-row"><strong>العنوان</strong> ${_escape(order.address)}</div>'}
      ${isKitchen ? '' : '<div class="meta-row"><strong>الدفع</strong> ${_escape(order.paymentMethod ?? 'كاش')}</div>'}
      <div class="meta-row"><strong>النوع</strong> ${order.orderType == OrderType.pickup ? 'استلام' : 'توصيل'}</div>
    </div>
    <div class="divider dashed"></div>
    $itemsBlock
    $totalsBlock
    <div class="divider dashed"></div>
    <div class="footer">${isKitchen ? '— المطبخ —' : 'شكراً لزيارتكم'}</div>
    <div class="footer-sub">Almenupro POS</div>
  </div>
</body>
</html>''';
  }

  static const _thermalCss = '''
    * { box-sizing: border-box; margin: 0; padding: 0; }
    @page {
      size: 80mm auto;
      margin: 2mm 3mm;
    }
    html, body {
      background: #fff;
      color: #000;
      -webkit-print-color-adjust: exact;
      print-color-adjust: exact;
    }
    body {
      font-family: 'Courier New', Courier, monospace;
      margin: 0 auto;
      padding: 4mm 3mm;
    }
    body.paper-80 { width: 80mm; max-width: 80mm; font-size: 12px; }
    body.paper-58 { width: 58mm; max-width: 58mm; font-size: 10px; }
    body.paper-58 .brand { font-size: 13px; }
    body.paper-58 .kitchen-name { font-size: 14px !important; }

    .receipt-root { width: 100%; }
    .receipt-header { text-align: center; margin-bottom: 6px; }
    .brand {
      font-size: 16px;
      font-weight: bold;
      letter-spacing: 0.5px;
      margin-bottom: 4px;
    }
    .receipt-title {
      text-align: center;
      font-weight: bold;
      font-size: 13px;
      margin: 6px 0;
      padding: 4px 0;
      border-top: 2px solid #000;
      border-bottom: 2px solid #000;
    }
    .order-meta { line-height: 1.55; margin: 6px 0; }
    .meta-row { margin: 2px 0; word-break: break-word; }
    .divider { margin: 6px 0; }
    .divider.dashed { border-top: 1px dashed #000; }

    .items-table { width: 100%; border-collapse: collapse; margin: 4px 0; }
    .items-table th, .items-table td {
      padding: 3px 2px;
      text-align: right;
      vertical-align: top;
      border-bottom: 1px dotted #999;
    }
    .items-table th { font-size: 10px; font-weight: bold; }
    .items-table .qty { width: 28px; white-space: nowrap; font-weight: bold; }
    .items-table .price { width: 42px; text-align: left; white-space: nowrap; }
    .addon { font-size: 10px; color: #333; margin-top: 2px; padding-right: 4px; }
    .note {
      font-size: 11px;
      font-weight: bold;
      margin-top: 3px;
      padding: 2px 4px;
      background: #eee;
    }

    .kitchen-items { margin: 6px 0; }
    .kitchen-item {
      display: flex;
      gap: 8px;
      padding: 8px 0;
      border-bottom: 2px dashed #000;
    }
    .kitchen-qty {
      font-size: 22px;
      font-weight: bold;
      min-width: 36px;
      line-height: 1.1;
    }
    .kitchen-name {
      font-size: 18px;
      font-weight: bold;
      line-height: 1.25;
    }
    .kitchen-ticket .addon { font-size: 12px; margin-top: 4px; }
    .kitchen-ticket .note {
      font-size: 14px;
      margin-top: 6px;
      padding: 4px 6px;
      border: 2px solid #000;
      background: #fff;
    }

    .totals { margin-top: 8px; line-height: 1.7; }
    .total-row {
      display: flex;
      justify-content: space-between;
      gap: 8px;
    }
    .total-row.grand {
      font-size: 14px;
      font-weight: bold;
      margin-top: 4px;
      padding-top: 4px;
      border-top: 2px solid #000;
    }

    .footer {
      text-align: center;
      font-weight: bold;
      margin-top: 8px;
      font-size: 12px;
    }
    .footer-sub {
      text-align: center;
      font-size: 9px;
      color: #666;
      margin-top: 4px;
    }

    @media print {
      html, body {
        width: 80mm !important;
        max-width: 80mm !important;
        margin: 0 !important;
        padding: 0 !important;
        background: #fff !important;
      }
      body.paper-58 {
        width: 58mm !important;
        max-width: 58mm !important;
      }
      @page {
        size: 80mm auto;
        margin: 2mm 3mm;
      }
      body.paper-58 @page {
        size: 58mm auto;
      }
      .receipt-root {
        width: 100% !important;
      }
      .no-print { display: none !important; }
    }
  ''';

  static String _escape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}
