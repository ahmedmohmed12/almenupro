import 'package:intl/intl.dart';

import '../models/invoice_language.dart';
import '../models/order.dart';
import '../services/pos_print_settings_service.dart';

enum PosReceiptKind { kitchen, customer }

enum PosReceiptPaperWidth { mm80, mm58 }

class PosReceiptHtml {
  static String build({
    required Order order,
    required String restaurantName,
    required PosReceiptKind kind,
    String? restaurantPhone,
    String? restaurantAddress,
    String? restaurantLogoUrl,
    PosReceiptPaperWidth? paperWidth,
    double? widthMm,
    PosPrintFontSize fontSize = PosPrintFontSize.medium,
    InvoiceLanguage language = InvoiceLanguage.arabic,
  }) {
    final ar = language.isArabic;
    final resolvedWidth = widthMm ??
        (paperWidth == PosReceiptPaperWidth.mm58 ? 58.0 : 80.0);
    final w = resolvedWidth.clamp(40.0, 120.0);
    final time = DateFormat('hh:mm a').format(order.createdAt.toLocal());
    final dateLine = DateFormat('yyyy-MM-dd').format(order.createdAt.toLocal());
    final orderId = order.invoiceNumber ?? order.id;
    final isKitchen = kind == PosReceiptKind.kitchen;
    final title = isKitchen
        ? (ar ? 'تذكرة المطبخ' : 'Kitchen ticket')
        : (ar ? 'فاتورة' : 'Invoice');
    final fonts = _fontScale(fontSize, w);
    final currency = ar ? 'د.ك' : 'KWD';
    final langAttr = ar ? 'ar' : 'en';
    final dirAttr = ar ? 'rtl' : 'ltr';

    final rows = order.items.map((item) {
      final addons = item.selectedOptions
          .map(
            (option) =>
                '<div class="addon">+ ${_escape(option.group)}: ${_escape(option.name)}</div>',
          )
          .join('');
      final notes = item.specialNotes?.trim().isNotEmpty ?? false
          ? '<div class="note">${_escape(item.specialNotes!.trim())}</div>'
          : '';

      if (isKitchen) {
        return '''
        <div class="kitchen-item">
          <div class="kitchen-qty">${item.quantity}</div>
          <div class="kitchen-details">
            <div class="kitchen-name">${_escape(item.name)}</div>
            $addons$notes
          </div>
        </div>''';
      }

      return '''
        <div class="item-row">
          <div class="item-main">
            <span class="qty">${item.quantity}</span>
            <span class="item-name">${_escape(item.name)}</span>
          </div>
          <div class="price">${item.lineTotal.toStringAsFixed(3)}</div>
        </div>
        $addons$notes''';
    }).join();

    final subtotal = order.subtotal ?? order.totalPrice;
    final deliveryFee = order.deliveryFee ?? 0;
    final logo = (restaurantLogoUrl ?? '').trim();
    final logoHtml = logo.isNotEmpty
        ? '<img class="logo" src="${_escape(logo)}" alt="">'
        : '';
    final phoneLine = restaurantPhone?.trim().isNotEmpty ?? false
        ? '<div class="store-meta">${_escape(restaurantPhone!.trim())}</div>'
        : '';
    final addressLine = restaurantAddress?.trim().isNotEmpty ?? false
        ? '<div class="store-meta">${_escape(restaurantAddress!.trim())}</div>'
        : '';

    final orderTypeLabel = switch (order.orderType) {
      OrderType.pickup => ar ? 'استلام' : 'Pickup',
      OrderType.dineIn => ar ? 'صالة' : 'Dine-in',
      OrderType.delivery => ar ? 'توصيل' : 'Delivery',
    };
    final defaultPayment = ar ? 'كاش' : 'Cash';

    final itemsBlock = isKitchen
        ? '<div class="kitchen-items">$rows</div>'
        : '<div class="items">$rows</div>';

    final totalsBlock = isKitchen
        ? ''
        : '''
  <div class="totals">
    <div class="total-row"><span>${ar ? 'المجموع' : 'Subtotal'}</span><span>${subtotal.toStringAsFixed(3)}</span></div>
    ${deliveryFee > 0 ? '<div class="total-row"><span>${ar ? 'التوصيل' : 'Delivery'}</span><span>${deliveryFee.toStringAsFixed(3)}</span></div>' : ''}
    <div class="total-row grand"><span>${ar ? 'الإجمالي' : 'Total'}</span><span>${order.totalPrice.toStringAsFixed(3)} $currency</span></div>
  </div>''';

    final customerBlock = isKitchen
        ? ''
        : '''
    <div class="customer">
      <div class="customer-name">${_escape(order.customerName)}</div>
      ${_customerAddressHtml(order, ar: ar)}
      <div class="customer-phone">${_escape(order.phone)}</div>
    </div>''';

    return '''
<!DOCTYPE html>
<html lang="$langAttr" dir="$dirAttr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$title — ${_escape(restaurantName)}</title>
  <style>
    ${_thermalCss(widthMm: w, fonts: fonts)}
  </style>
</head>
<body class="${isKitchen ? 'kitchen-ticket' : 'customer-receipt'}">
  <div id="receipt-root" class="receipt-root">
    <div class="receipt-header">
      $logoHtml
      <div class="brand">${_escape(restaurantName)}</div>
      $phoneLine
      $addressLine
    </div>
    <div class="status-row">
      <span class="pill">${_escape(orderTypeLabel)}</span>
      <span class="pill">$time</span>
      <span class="pill">${_escape(order.paymentMethod ?? defaultPayment)}</span>
    </div>
    <div class="order-no">#${_escape(orderId)}</div>
    $customerBlock
    <div class="divider"></div>
    $itemsBlock
    $totalsBlock
    <div class="divider"></div>
    <div class="footer-meta">$dateLine · ${ar ? 'رقم الطلب' : 'Order'} ${_escape(orderId)}</div>
    <div class="footer">${isKitchen ? (ar ? '— المطبخ —' : '— Kitchen —') : (ar ? 'شكراً لطلبك' : 'Thank you')}</div>
    <div class="footer-sub">${_escape(restaurantName)}</div>
  </div>
</body>
</html>''';
  }

  static String _customerAddressHtml(Order order, {required bool ar}) {
    final details = order.addressDetails;
    final parts = <String>[];
    if (order.areaName?.trim().isNotEmpty ?? false) {
      parts.add(order.areaName!.trim());
    }
    if (order.governorate?.trim().isNotEmpty ?? false) {
      parts.add(order.governorate!.trim());
    }
    final streetBits = <String>[];
    if (details.block.trim().isNotEmpty) {
      streetBits.add(ar ? 'قطعة ${details.block.trim()}' : 'block ${details.block.trim()}');
    }
    if (details.street.trim().isNotEmpty) {
      streetBits.add(ar ? 'شارع ${details.street.trim()}' : 'street ${details.street.trim()}');
    }
    if (details.houseNumber.trim().isNotEmpty) {
      streetBits.add(
        ar ? 'بيت ${details.houseNumber.trim()}' : details.houseNumber.trim(),
      );
    }
    if (details.avenue.trim().isNotEmpty) {
      streetBits.add(ar ? 'جادة ${details.avenue.trim()}' : 'avenue ${details.avenue.trim()}');
    }
    if (details.floorApartment.trim().isNotEmpty) {
      streetBits.add(
        ar ? 'طابق ${details.floorApartment.trim()}' : details.floorApartment.trim(),
      );
    }

    final lines = <String>[];
    if (streetBits.isNotEmpty) lines.add(streetBits.join(', '));
    if (parts.isNotEmpty) lines.add(parts.join(', '));
    if (lines.isEmpty && order.address.trim().isNotEmpty) {
      lines.add(order.address.trim());
    }
    if (lines.isEmpty) return '';
    return lines.map((line) => '<div class="addr">${_escape(line)}</div>').join();
  }

  static ({double base, double brand, double kitchen, double title, double grand, double orderNo})
      _fontScale(PosPrintFontSize size, double widthMm) {
    final narrow = widthMm < 65;
    final factor = switch (size) {
      PosPrintFontSize.small => 0.85,
      PosPrintFontSize.medium => 1.0,
      PosPrintFontSize.large => 1.2,
    };
    final base = (narrow ? 10.0 : 12.0) * factor;
    return (
      base: base,
      brand: (narrow ? 16.0 : 20.0) * factor,
      kitchen: (narrow ? 15.0 : 18.0) * factor,
      title: (narrow ? 12.0 : 13.0) * factor,
      grand: (narrow ? 13.0 : 15.0) * factor,
      orderNo: (narrow ? 22.0 : 28.0) * factor,
    );
  }

  static String _thermalCss({
    required double widthMm,
    required ({
      double base,
      double brand,
      double kitchen,
      double title,
      double grand,
      double orderNo,
    }) fonts,
  }) {
    final w = widthMm.toStringAsFixed(2);
    return '''
    * { box-sizing: border-box; margin: 0; padding: 0; }
    @page { size: ${w}mm auto; margin: 2mm 2.5mm; }
    html, body {
      background: #fff;
      color: #000;
      -webkit-print-color-adjust: exact;
      print-color-adjust: exact;
    }
    body {
      font-family: Arial, 'Noto Naskh Arabic', Tahoma, sans-serif;
      margin: 0 auto;
      padding: 3mm 2mm 8mm;
      width: ${w}mm;
      max-width: ${w}mm;
      font-size: ${fonts.base.toStringAsFixed(1)}px;
    }
    .receipt-root { width: 100%; }
    .receipt-header { text-align: center; margin-bottom: 8px; }
    .logo {
      max-width: 42mm;
      max-height: 18mm;
      object-fit: contain;
      margin: 0 auto 4px;
      display: block;
    }
    .brand {
      font-size: ${fonts.brand.toStringAsFixed(1)}px;
      font-weight: 900;
      letter-spacing: 0.2px;
      line-height: 1.15;
    }
    .store-meta { font-size: ${(fonts.base * 0.85).toStringAsFixed(1)}px; color: #222; }
    .status-row {
      display: flex;
      justify-content: space-between;
      gap: 4px;
      margin: 8px 0 4px;
      font-size: ${(fonts.base * 0.85).toStringAsFixed(1)}px;
      font-weight: 700;
    }
    .pill { flex: 1; text-align: center; }
    .order-no {
      text-align: center;
      font-weight: 900;
      font-size: ${fonts.orderNo.toStringAsFixed(1)}px;
      line-height: 1.1;
      margin: 6px 0 8px;
    }
    .customer { text-align: center; margin-bottom: 8px; line-height: 1.4; }
    .customer-name { font-weight: 800; font-size: ${(fonts.base * 1.05).toStringAsFixed(1)}px; }
    .addr, .customer-phone { word-break: break-word; }
    .divider { border-top: 1px solid #000; margin: 8px 0; }

    .item-row {
      display: flex;
      justify-content: space-between;
      gap: 8px;
      align-items: flex-start;
      margin: 4px 0;
    }
    .item-main { display: flex; gap: 6px; flex: 1; }
    .qty { font-weight: 800; min-width: 14px; }
    .item-name { font-weight: 700; }
    .price { white-space: nowrap; font-weight: 700; }
    .addon { font-size: ${(fonts.base * 0.85).toStringAsFixed(1)}px; padding-inline-start: 18px; }
    .note { font-size: ${(fonts.base * 0.9).toStringAsFixed(1)}px; font-weight: 700; padding-inline-start: 18px; }

    .kitchen-item {
      display: flex;
      gap: 8px;
      padding: 8px 0;
      border-bottom: 1px dashed #000;
    }
    .kitchen-qty {
      font-size: ${(fonts.kitchen * 1.2).toStringAsFixed(1)}px;
      font-weight: 900;
      min-width: 28px;
    }
    .kitchen-name {
      font-size: ${fonts.kitchen.toStringAsFixed(1)}px;
      font-weight: 800;
    }

    .totals { margin-top: 6px; }
    .total-row {
      display: flex;
      justify-content: space-between;
      gap: 8px;
      margin: 2px 0;
    }
    .total-row.grand {
      font-size: ${fonts.grand.toStringAsFixed(1)}px;
      font-weight: 900;
      margin-top: 4px;
      padding-top: 4px;
      border-top: 2px solid #000;
    }
    .footer-meta {
      text-align: center;
      font-size: ${(fonts.base * 0.85).toStringAsFixed(1)}px;
      margin-bottom: 4px;
    }
    .footer {
      text-align: center;
      font-weight: 800;
      margin-top: 4px;
    }
    .footer-sub {
      text-align: center;
      font-size: ${(fonts.base * 0.85).toStringAsFixed(1)}px;
      margin-top: 2px;
    }

    @media print {
      html, body {
        width: ${w}mm !important;
        max-width: ${w}mm !important;
        margin: 0 !important;
        padding: 2mm 2mm 6mm !important;
        background: #fff !important;
      }
      @page { size: ${w}mm auto; margin: 2mm 2mm; }
    }
  ''';
  }

  static String _escape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}
