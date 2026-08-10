import '../models/cart_item.dart';
import '../models/delivery_address_details.dart';
import '../models/menu_item.dart';

class WhatsAppOrderMessage {
  static String build({
    required String restaurantName,
    required String invoiceNumber,
    required String customerName,
    required String phone,
    required String paymentMethod,
    required String orderTime,
    required List<CartItem> cartItems,
    required double subtotal,
    required double deliveryFee,
    required double grandTotal,
    required String addressArabic,
    required String addressEnglish,
  }) {
    final itemsAr = StringBuffer();
    final itemsEn = StringBuffer();

    for (final item in cartItems) {
      final nameAr = item.menuItem.localizedName('ar');
      final nameEn = item.menuItem.localizedName('en');
      final lineTotal = item.totalPrice.toStringAsFixed(3);
      itemsAr.writeln('• $nameAr x${item.quantity} ($lineTotal د.ك)');
      itemsEn.writeln('• $nameEn x${item.quantity} ($lineTotal KWD)');
    }

    final paymentAr = paymentMethod == 'K-Net' ? 'K-Net' : 'كاش';
    final paymentEn = paymentMethod == 'K-Net' ? 'K-Net' : 'Cash';

    return '''
🧾 *فاتورة طلب جديدة - $restaurantName*
🧾 *New Order Invoice - $restaurantName*
----------------------------------
📌 *رقم الفاتورة / Invoice #:* #$invoiceNumber
👤 *اسم العميل / Customer:* $customerName
📞 *رقم الهاتف / Phone:* $phone
📍 *عنوان التوصيل / Delivery address:*
   🇰🇼 $addressArabic
   🇬🇧 $addressEnglish
🚚 *رسوم التوصيل / Delivery fee:* ${deliveryFee.toStringAsFixed(3)} د.ك / KWD
💳 *طريقة الدفع / Payment:* $paymentAr / $paymentEn

🕒 *وقت الطلب / Order time:* $orderTime

🛒 *تفاصيل الطلب / Order details:*
$itemsAr
$itemsEn
----------------------------------
🧮 *المجموع الفرعي / Subtotal:* ${subtotal.toStringAsFixed(3)} د.ك / KWD
🚚 *التوصيل / Delivery:* ${deliveryFee.toStringAsFixed(3)} د.ك / KWD
💰 *الإجمالي النهائي / Grand total:* ${grandTotal.toStringAsFixed(3)} د.ك / KWD
----------------------------------
شكراً لطلبكم من $restaurantName! ❤️
Thank you for ordering from $restaurantName! ❤️
''';
  }

  static String formatAddressEnglish({
    required DeliveryAddressDetails details,
    required String governorate,
    required String areaName,
  }) {
    return details.formatEnglish(
      governorate: governorate,
      areaName: areaName,
    );
  }
}
