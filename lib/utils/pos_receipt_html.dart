import 'package:intl/intl.dart';

import '../models/invoice_language.dart';
import '../models/order.dart';
import '../services/pos_print_settings_service.dart';
import 'kitchen_modification_delta.dart';

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
    final resolvedWidth =
        widthMm ?? (paperWidth == PosReceiptPaperWidth.mm58 ? 58.0 : 80.0);
    final w = resolvedWidth.clamp(40.0, 120.0);
    final time = DateFormat('hh:mm a').format(order.createdAt.toLocal());
    final dateLine = DateFormat('yyyy-MM-dd').format(order.createdAt.toLocal());
    final orderId = order.invoiceNumber ?? order.id;
    final isKitchen = kind == PosReceiptKind.kitchen;
    final title = isKitchen
        ? (ar ? 'تذكرة المطبخ' : 'Kitchen ticket')
        : (ar ? 'فاتورة' : 'Invoice');
    // storeName is cashier/admin only and is intentionally omitted here.
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
      OrderType.scheduledDelivery => ar ? 'توصيل مجدول' : 'Scheduled delivery',
    };
    final defaultPayment = ar ? 'كاش' : 'Cash';
    final paymentLabel = (order.paymentMethod ?? '').trim().isEmpty
        ? defaultPayment
        : order.paymentMethod!.trim();
    final settlement = order.settlementLabel;
    final settlementText = settlement == 'CASH ON DELIVERY'
        ? (ar
            ? 'الدفع عند الاستلام — CASH ON DELIVERY'
            : 'CASH ON DELIVERY')
        : (ar ? 'مدفوع مسبقاً — PREPAID / ONLINE' : 'PREPAID / ONLINE');
    final settlementHtml = settlement.isEmpty
        ? ''
        : '<div class="settlement">${_escape(settlementText)}</div>';
    final payable = order.customerPayable;
    final instructions = order.deliveryInstructions.trim();
    final tableLabel = _tableLabel(order, ar: ar);
    final isTableKitchen = isKitchen && tableLabel != null;

    final itemsBlock = isKitchen
        ? '<div class="kitchen-items">$rows</div>'
        : '<div class="items">$rows</div>';

    final totalsBlock = isKitchen
        ? ''
        : '''
  <div class="totals">
    <div class="total-row"><span>${ar ? 'المجموع' : 'Subtotal'}</span><span>${subtotal.toStringAsFixed(3)}</span></div>
    ${deliveryFee > 0 ? '<div class="total-row"><span>${ar ? 'التوصيل' : 'Delivery'}</span><span>${deliveryFee.toStringAsFixed(3)}</span></div>' : ''}
    <div class="total-row grand"><span>${ar ? 'المطلوب من العميل' : 'Customer payable'}</span><span>${payable.toStringAsFixed(3)} $currency</span></div>
  </div>''';

    final hasCustomerDetails =
        order.customerName.trim().isNotEmpty ||
        order.phone.trim().isNotEmpty ||
        order.address.trim().isNotEmpty;
    final showCustomerDetails =
        !isKitchen ||
        (order.orderType == OrderType.delivery && hasCustomerDetails);
    final customerBlock = !showCustomerDetails
        ? ''
        : '''
    <div class="customer">
      <div class="customer-name">${_escape(order.customerName)}</div>
      ${_customerAddressHtml(order, ar: ar)}
      <div class="customer-phone">${_escape(order.phone)}</div>
      ${instructions.isEmpty ? '' : '<div class="note">${_escape(ar ? 'تعليمات التوصيل: $instructions' : 'Delivery instructions: $instructions')}</div>'}
    </div>''';

    final tableKitchenBlock = isTableKitchen
        ? '''
    <div class="table-highlight">
      <div class="table-label">${ar ? 'رقم الطاولة' : 'Table'}</div>
      <div class="table-value">${_escape(tableLabel)}</div>
      <div class="payment-label">${ar ? 'طريقة الدفع' : 'Payment'}</div>
      <div class="payment-value">${_escape(paymentLabel)}</div>
    </div>'''
        : '';

    final statusRow = isTableKitchen
        ? '''
    <div class="status-row">
      <span class="pill">${_escape(orderTypeLabel)}</span>
      <span class="pill">$time</span>
    </div>'''
        : '''
    <div class="status-row">
      <span class="pill">${_escape(orderTypeLabel)}</span>
      <span class="pill">$time</span>
      <span class="pill">${_escape(paymentLabel)}</span>
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
    $settlementHtml
    $statusRow
    ${isKitchen && (order.targetKitchenName ?? '').trim().isNotEmpty ? '<div class="order-no">${_escape(order.targetKitchenName!.trim())}</div>' : ''}
    $tableKitchenBlock
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

  static String? _tableLabel(Order order, {required bool ar}) {
    final number = (order.tableNumber ?? '').trim();
    if (number.isNotEmpty) {
      return ar ? 'طاولة $number' : 'Table $number';
    }
    final tableId = (order.tableId ?? '').trim();
    final isDineIn = order.orderType == OrderType.dineIn || tableId.isNotEmpty;
    if (!isDineIn) return null;

    final address = order.address.trim();
    final addressMatch = RegExp(r'طاولة\s*([^\s—\-]+)').firstMatch(address);
    if (addressMatch != null) {
      final value = addressMatch.group(1)?.trim() ?? '';
      if (value.isNotEmpty) {
        return ar ? 'طاولة $value' : 'Table $value';
      }
    }

    final name = order.customerName.trim();
    if (name.startsWith('طاولة') || name.toLowerCase().startsWith('table')) {
      return name;
    }
    if (name.isNotEmpty) {
      return ar ? 'طاولة $name' : 'Table $name';
    }
    return ar ? 'طاولة' : 'Table';
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
      streetBits.add(
        ar ? 'قطعة ${details.block.trim()}' : 'block ${details.block.trim()}',
      );
    }
    if (details.street.trim().isNotEmpty) {
      streetBits.add(
        ar
            ? 'شارع ${details.street.trim()}'
            : 'street ${details.street.trim()}',
      );
    }
    if (details.houseNumber.trim().isNotEmpty) {
      streetBits.add(
        ar ? 'بيت ${details.houseNumber.trim()}' : details.houseNumber.trim(),
      );
    }
    if (details.avenue.trim().isNotEmpty) {
      streetBits.add(
        ar
            ? 'جادة ${details.avenue.trim()}'
            : 'avenue ${details.avenue.trim()}',
      );
    }
    if (details.floorApartment.trim().isNotEmpty) {
      streetBits.add(
        ar
            ? 'طابق ${details.floorApartment.trim()}'
            : details.floorApartment.trim(),
      );
    }

    final lines = <String>[];
    if (streetBits.isNotEmpty) lines.add(streetBits.join(', '));
    if (parts.isNotEmpty) lines.add(parts.join(', '));
    final rawAddress = order.address.trim();
    if (lines.isEmpty && rawAddress.isNotEmpty) {
      lines.add(rawAddress);
    }
    final shown = lines.isEmpty ? (ar ? '—' : '—') : lines.join(' · ');
    return '<div class="addr"><strong>${ar ? 'العنوان' : 'Address'}:</strong> ${_escape(shown)}</div>';
  }

  static ({
    double base,
    double brand,
    double kitchen,
    double title,
    double grand,
    double orderNo,
  })
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
    })
    fonts,
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
    .settlement {
      border: 2px solid #111;
      font-size: ${fonts.grand.toStringAsFixed(1)}px;
      font-weight: 800;
      margin: 8px 0;
      padding: 6px;
      text-align: center;
    }
    .order-no {
      text-align: center;
      font-weight: 900;
      font-size: ${fonts.orderNo.toStringAsFixed(1)}px;
      line-height: 1.1;
      margin: 6px 0 8px;
    }
    .table-highlight {
      text-align: center;
      margin: 8px 0 10px;
      padding: 8px 4px;
      border: 2px solid #000;
    }
    .table-label,
    .payment-label {
      font-size: ${(fonts.base * 0.95).toStringAsFixed(1)}px;
      font-weight: 800;
      margin-top: 2px;
    }
    .table-value {
      font-size: ${(fonts.orderNo * 1.05).toStringAsFixed(1)}px;
      font-weight: 900;
      line-height: 1.05;
      margin: 2px 0 8px;
    }
    .payment-value {
      font-size: ${(fonts.orderNo * 0.85).toStringAsFixed(1)}px;
      font-weight: 900;
      line-height: 1.05;
      margin-bottom: 2px;
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

  static String buildKitchenModification({
    required Order order,
    required KitchenModificationDelta delta,
    required String restaurantName,
    String? restaurantPhone,
    PosReceiptPaperWidth? paperWidth,
    double? widthMm,
    PosPrintFontSize fontSize = PosPrintFontSize.medium,
    InvoiceLanguage language = InvoiceLanguage.arabic,
  }) {
    if (delta.isEmpty) return '';
    final ar = language.isArabic;
    final resolvedWidth =
        widthMm ?? (paperWidth == PosReceiptPaperWidth.mm58 ? 58.0 : 80.0);
    final w = resolvedWidth.clamp(40.0, 120.0);
    final fonts = _fontScale(fontSize, w);
    final orderId = order.invoiceNumber ?? order.id;
    final time = DateFormat('hh:mm a').format(DateTime.now().toLocal());
    final dateLine = DateFormat('yyyy-MM-dd').format(DateTime.now().toLocal());

    String section(String title, List<KitchenModificationLine> lines) {
      if (lines.isEmpty) return '';
      final rows = lines
          .map(
            (line) => '''
        <div class="kitchen-item">
          <div class="kitchen-qty">${line.quantity}</div>
          <div class="kitchen-details">
            <div class="kitchen-name">${_escape(line.name)}</div>
            ${line.detail != null ? '<div class="mod-detail">${_escape(line.detail!)}</div>' : ''}
            ${(line.notes ?? '').trim().isNotEmpty ? '<div class="note">${_escape(line.notes!.trim())}</div>' : ''}
          </div>
        </div>''',
          )
          .join();
      return '''
      <div class="mod-section">
        <div class="mod-section-title">${_escape(title)}</div>
        <div class="kitchen-items">$rows</div>
      </div>''';
    }

    final body = [
      section(ar ? 'إضافات' : 'Added', delta.added),
      section(ar ? 'تعديلات' : 'Changed', delta.changed),
      section(ar ? 'إلغاء / تقليل' : 'Void / reduced', delta.voided),
    ].join();

    final tableLabel = _tableLabel(order, ar: ar);
    final tableLine = tableLabel != null
        ? '<div class="order-no">${_escape(tableLabel)}</div>'
        : '';

    return '''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${ar ? 'فاتورة معدّلة' : 'Modified ticket'}</title>
  <style>
    ${_thermalCss(widthMm: w, fonts: fonts)}
    .mod-banner {
      border: 3px solid #000;
      text-align: center;
      font-weight: 900;
      font-size: ${(fonts.kitchen * 1.05).toStringAsFixed(1)}px;
      padding: 8px 4px;
      margin: 8px 0;
      line-height: 1.25;
    }
    .mod-subtitle {
      text-align: center;
      font-size: ${(fonts.base * 0.9).toStringAsFixed(1)}px;
      font-weight: 700;
      margin-bottom: 6px;
    }
    .mod-section { margin: 8px 0; }
    .mod-section-title {
      font-weight: 800;
      font-size: ${fonts.title.toStringAsFixed(1)}px;
      border-bottom: 2px dashed #000;
      margin-bottom: 4px;
      padding-bottom: 2px;
    }
    .mod-detail {
      font-size: ${(fonts.base * 0.9).toStringAsFixed(1)}px;
      font-weight: 700;
    }
  </style>
</head>
<body class="kitchen-ticket">
  <div class="receipt-root">
    <div class="receipt-header">
      <div class="brand">${_escape(restaurantName)}</div>
      ${restaurantPhone?.trim().isNotEmpty == true ? '<div class="store-meta">${_escape(restaurantPhone!.trim())}</div>' : ''}
    </div>
    <div class="mod-banner">${ar ? 'فاتورة معدّلة' : 'MODIFIED TICKET'}</div>
    <div class="mod-subtitle">${ar ? 'تحديث على طلب موجود — لا تُعِد تحضير ما سبق إرساله' : 'Update only — do not re-prepare prior items'}</div>
    <div class="order-no">#${_escape(orderId)}</div>
    $tableLine
    <div class="status-row"><span class="pill">$time</span></div>
    <div class="divider"></div>
    $body
    <div class="divider"></div>
    <div class="footer-meta">$dateLine · ${_escape(order.customerName)}</div>
    <div class="footer">${ar ? '— تحديث مطبخ —' : '— Kitchen update —'}</div>
  </div>
</body>
</html>''';
  }

  static String _escape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}
