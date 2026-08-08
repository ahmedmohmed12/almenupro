import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/locale_provider.dart';

class AppStrings {
  const AppStrings(this.localeCode);

  final String localeCode;

  bool get isArabic => localeCode.startsWith('ar');

  static AppStrings of(BuildContext context) {
    final locale = context.watch<LocaleProvider>().localeCode;
    return AppStrings(locale);
  }

  String get all => isArabic ? 'الكل' : 'All';
  String get menuTagline => isArabic ? 'قائمة الطعام' : 'Menu';
  String menuTaglineFor(String restaurantName) =>
      isArabic ? 'قائمة الطعام — $restaurantName' : 'Menu — $restaurantName';
  String get defaultTagline =>
      isArabic ? 'قائمة الطعام — ميني بايتس وكوكيز' : 'Menu — Mini bites & cookies';
  String get refresh => isArabic ? 'تحديث' : 'Refresh';
  String get noDescription => isArabic ? 'لا يوجد وصف' : 'No description';
  String get noItemsInCategory =>
      isArabic ? 'لا توجد أصناف في هذا التصنيف' : 'No items in this category';
  String get noItemsAvailable =>
      isArabic ? 'لا توجد أصناف متاحة حالياً' : 'No items available right now';
  String get restaurantNotFound =>
      isArabic ? 'المطعم غير موجود أو الرابط غير صحيح' : 'Restaurant not found or invalid link';
  String addedToCart(String itemName) =>
      isArabic ? 'تمت إضافة "$itemName" إلى السلة' : '"$itemName" added to cart';
  String get continueOrder => isArabic ? 'متابعة الطلب' : 'Checkout';
  String get currency => isArabic ? 'د.ك' : 'KWD';

  String get checkoutTitle => isArabic ? 'إتمام الطلب' : 'Complete Order';
  String get customerName => isArabic ? 'اسم العميل' : 'Customer name';
  String get phone => isArabic ? 'رقم الهاتف' : 'Phone number';
  String get deliveryAddress => isArabic ? 'عنوان التوصيل' : 'Delivery address';
  String get governorate => isArabic ? 'المحافظة' : 'Governorate';
  String get area => isArabic ? 'المنطقة' : 'Area';
  String get noAreasForGovernorate =>
      isArabic ? 'لا توجد مناطق لهذه المحافظة' : 'No areas for this governorate';
  String get block => isArabic ? 'القطعة (Block)' : 'Block';
  String get street => isArabic ? 'الشارع (Street)' : 'Street';
  String get avenue => isArabic ? 'الجادة (Avenue) — اختياري' : 'Avenue (optional)';
  String get houseNumber => isArabic ? 'رقم البيت / المبنى' : 'House / building number';
  String get floorApartment =>
      isArabic ? 'الطابق / الشقة — اختياري' : 'Floor / apartment (optional)';
  String get paymentMethod => isArabic ? 'طريقة الدفع' : 'Payment method';
  String get cash => isArabic ? 'كاش' : 'Cash';
  String get knet => 'K-Net';
  String get subtotal => isArabic ? 'المجموع الفرعي' : 'Subtotal';
  String get deliveryFee => isArabic ? 'رسوم التوصيل' : 'Delivery fee';
  String get grandTotal => isArabic ? 'الإجمالي النهائي' : 'Grand total';
  String sendOrder(String total) =>
      isArabic ? 'إرسال الطلب $total د.ك' : 'Send order $total KWD';
  String get required => isArabic ? 'مطلوب' : 'Required';
  String get selectGovernorateAndArea =>
      isArabic ? 'يرجى اختيار المحافظة والمنطقة' : 'Please select governorate and area';
  String get orderSentViaWhatsapp =>
      isArabic ? 'تم إرسال الطلب عبر الواتساب' : 'Order sent via WhatsApp';
  String whatsappOpenFailed(String phone) => isArabic
      ? 'تعذر فتح الواتساب. رقم المطعم: $phone'
      : 'Could not open WhatsApp. Restaurant number: $phone';

  String paymentLabel(String value) {
    if (value == 'كاش' || value == 'Cash') return cash;
    return knet;
  }

  String paymentValueForApi(String displayLabel) {
    if (displayLabel == cash || displayLabel == 'Cash') return 'كاش';
    return 'K-Net';
  }
}
