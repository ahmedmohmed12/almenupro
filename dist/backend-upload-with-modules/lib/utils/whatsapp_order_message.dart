import '../models/cart_item.dart';
import '../models/invoice_language.dart';

/// WhatsApp order invoice — one language, same as the restaurant print setting.
class WhatsAppOrderMessage {
  static String build({
    required InvoiceLanguage language,
    required String restaurantName,
    required String invoiceNumber,
    required String customerName,
    required String phone,
    required String paymentMethod,
    required DateTime orderedAt,
    required List<CartItem> cartItems,
    required double subtotal,
    required double deliveryFee,
    required double grandTotal,
    required String address,
    double discountAmount = 0,
    double walletRedeemAmount = 0,
    String? orderId,
    String? frontendUrl,
  }) {
    final ar = language.isArabic;
    final currency = ar ? 'د.ك' : 'KWD';
    final time = _formatTime(orderedAt, ar: ar);
    final payment = _paymentLabel(paymentMethod, ar: ar);
    final items = _itemsBlock(cartItems, language: language, currency: currency);
    final lines = <String>[
      restaurantName.trim(),
      ar ? 'فاتورة #$invoiceNumber' : 'Invoice #$invoiceNumber',
      time,
      '',
      customerName.trim(),
      phone.trim(),
      if (address.trim().isNotEmpty) address.trim(),
      '',
      items,
      '',
      ar
          ? 'المجموع: ${_money(subtotal)} $currency'
          : 'Subtotal: ${_money(subtotal)} $currency',
    ];

    if (discountAmount > 0.0005) {
      lines.add(
        ar
            ? 'الخصم: -${_money(discountAmount)} $currency'
            : 'Discount: -${_money(discountAmount)} $currency',
      );
    }
    if (walletRedeemAmount > 0.0005) {
      lines.add(
        ar
            ? 'المحفظة: -${_money(walletRedeemAmount)} $currency'
            : 'Wallet: -${_money(walletRedeemAmount)} $currency',
      );
    }
    if (deliveryFee > 0) {
      lines.add(
        ar
            ? 'التوصيل: ${_money(deliveryFee)} $currency'
            : 'Delivery: ${_money(deliveryFee)} $currency',
      );
    }

    lines.addAll([
      ar
          ? '*الإجمالي: ${_money(grandTotal)} $currency*'
          : '*Total: ${_money(grandTotal)} $currency*',
      '',
      '$payment · ${ar ? 'توصيل' : 'Delivery'}',
      '',
      ar ? 'شكراً لطلبك' : 'Thank you',
    ]);

    final origin = ((frontendUrl ?? '').trim().isEmpty
            ? 'https://frontend-six-lime-13.vercel.app'
            : frontendUrl!.trim())
        .replaceAll(RegExp(r'/+$'), '');
    final ref = (orderId ?? '').trim();
    if (ref.isNotEmpty) {
      lines.addAll([
        '',
        '🔗 رابط قبول الأوردر الفوري:',
        '$origin/admin/orders/$ref',
      ]);
    }

    return lines.join('\n');
  }

  static String _itemsBlock(
    List<CartItem> cartItems, {
    required InvoiceLanguage language,
    required String currency,
  }) {
    final buffer = StringBuffer();
    for (final item in cartItems) {
      final name = item.menuItem.localizedName(language.code);
      buffer.writeln(
        '${item.quantity}× $name  ${_money(item.totalPrice)} $currency',
      );
      for (final option in item.selectedOptions) {
        final extra = option.price > 0
            ? ' (+${_money(option.price)} $currency)'
            : '';
        buffer.writeln('   + ${option.name}$extra');
      }
      final notes = item.specialNotes?.trim() ?? '';
      if (notes.isNotEmpty) {
        buffer.writeln('   $notes');
      }
    }
    return buffer.toString().trimRight();
  }

  static String _paymentLabel(String raw, {required bool ar}) {
    final value = raw.trim().toLowerCase();
    final isCash = value.contains('كاش') ||
        value.contains('cash') ||
        value == 'نقد' ||
        value == 'نقدي';
    if (isCash) return ar ? 'كاش' : 'Cash';
    if (value.contains('k-net') || value.contains('knet')) return 'K-Net';
    return raw.trim();
  }

  static String _formatTime(DateTime time, {required bool ar}) {
    final local = time.toLocal();
    final hour24 = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    if (ar) {
      final period = hour24 < 12 ? 'ص' : 'م';
      var hour12 = hour24 % 12;
      if (hour12 == 0) hour12 = 12;
      return '${hour12.toString().padLeft(2, '0')}:$minute $period';
    }
    final period = hour24 < 12 ? 'AM' : 'PM';
    var hour12 = hour24 % 12;
    if (hour12 == 0) hour12 = 12;
    return '${hour12.toString().padLeft(2, '0')}:$minute $period';
  }

  static String _money(double value) => value.toStringAsFixed(3);
}
