import '../models/delivery_address_details.dart';
import '../models/invoice_language.dart';
import '../models/order.dart';
import '../models/pos_role.dart';
import '../utils/pos_receipt_html.dart';
import 'admin_auth_service.dart';
import 'pos_operations_service.dart';
import 'pos_print_service.dart';
import 'pos_print_settings_service.dart';
import 'restaurant_settings_service.dart';

/// Central POS print entry — applies workstation printer settings.
abstract final class PosPrintHelper {
  static Future<void> ensureReady() async {
    await PosPrintSettingsService.instance.initialize();
    if (RestaurantSettingsService.instance.cached == null) {
      await RestaurantSettingsService.instance.load();
    }
  }

  static InvoiceLanguage get invoiceLanguage =>
      RestaurantSettingsService.instance.cached?.invoiceLanguage ??
      InvoiceLanguage.arabic;

  static PosPrintSettings get settings =>
      PosPrintSettingsService.instance.settings;

  static bool get canPrint =>
      PosOperationsService.instance.allows(PosPermissionKeys.printInvoice);

  static String get restaurantName {
    final name = AdminAuthService.instance.restaurantName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'AlMenuPro';
  }

  static String? get restaurantPhone {
    final settings = RestaurantSettingsService.instance.cached;
    final phone = settings?.fullWhatsappNumber.trim();
    if (phone != null && phone.isNotEmpty) return phone;
    return settings?.whatsappPhone.trim().isNotEmpty == true
        ? settings!.whatsappPhone.trim()
        : null;
  }

  static String? get restaurantAddress {
    final description =
        RestaurantSettingsService.instance.cached?.restaurantDescription.trim();
    if (description == null || description.isEmpty) return null;
    return description;
  }

  static String? get restaurantLogoUrl {
    final url = RestaurantSettingsService.instance.cached?.logoUrl.trim();
    if (url == null || url.isEmpty) return null;
    return url;
  }

  static String buildHtml({
    required Order order,
    required PosReceiptKind kind,
    PosPrintSettings? overrideSettings,
    InvoiceLanguage? language,
  }) {
    final cfg = overrideSettings ?? settings;
    return PosReceiptHtml.build(
      order: order,
      restaurantName: restaurantName,
      kind: kind,
      restaurantPhone: restaurantPhone,
      restaurantAddress: restaurantAddress,
      restaurantLogoUrl: restaurantLogoUrl,
      widthMm: cfg.widthMm,
      fontSize: cfg.fontSize,
      language: language ?? invoiceLanguage,
    );
  }

  static Future<void> printOrder({
    required Order order,
    required PosReceiptKind kind,
    PosPrintSettings? overrideSettings,
    InvoiceLanguage? language,
    bool ignorePermission = false,
  }) async {
    await ensureReady();
    if (!ignorePermission && !canPrint) return;

    final cfg = overrideSettings ?? settings;
    final html = buildHtml(
      order: order,
      kind: kind,
      overrideSettings: cfg,
      language: language,
    );
    if (html.trim().isEmpty) return;

    final copies = cfg.copies.clamp(1, 5);
    for (var i = 0; i < copies; i++) {
      await printPosReceiptHtml(html);
      if (i < copies - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 650));
      }
    }
  }

  static Future<void> printIfAuto({
    required Order order,
    required PosReceiptKind kind,
  }) async {
    await ensureReady();
    if (!canPrint) return;
    final cfg = settings;
    final enabled = kind == PosReceiptKind.kitchen
        ? cfg.autoPrintKitchen
        : cfg.autoPrintCustomer;
    if (!enabled) return;
    await printOrder(order: order, kind: kind);
  }

  static Order buildTestOrder({InvoiceLanguage? language}) {
    final ar = (language ?? invoiceLanguage).isArabic;
    return Order(
      id: 'test-print',
      customerName: ar ? 'خالد علي' : 'Khaled Ali',
      phone: '96555776269',
      address: ar ? 'قطعة 8، شارع 1، بيت 35' : 'block 8, street 1, 35',
      items: [
        OrderLineItem(
          menuItemId: 'test-1',
          name: ar ? 'بلاليط' : 'Balaleet',
          quantity: 1,
          unitPrice: 1.250,
          selectedOptions: const [],
        ),
        OrderLineItem(
          menuItemId: 'test-2',
          name: ar ? 'شاي كرك' : 'Karaks tea',
          quantity: 2,
          unitPrice: 0.350,
          selectedOptions: const [],
          specialNotes: ar ? 'بدون سكر' : 'No sugar',
        ),
      ],
      totalPrice: 1.950,
      orderType: OrderType.delivery,
      status: OrderStatus.confirmed,
      createdAt: DateTime.now().toUtc(),
      invoiceNumber: '5393',
      paymentMethod: ar ? 'كاش' : 'Cash',
      subtotal: 1.950,
      deliveryFee: 0,
      orderSource: 'pos',
      governorate: 'الفروانية',
      areaName: 'العارضية',
      addressDetails: const DeliveryAddressDetails(
        block: '8',
        street: '1',
        houseNumber: '35',
      ),
    );
  }
}
