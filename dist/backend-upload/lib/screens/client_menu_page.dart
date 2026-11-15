import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../providers/locale_provider.dart';
import '../services/api_service.dart';
import '../services/menu_storage_service.dart';
import '../services/orders_demo_service.dart';
import '../utils/whatsapp_launcher.dart';
import '../widgets/network_menu_image.dart';
import '../widgets/language_toggle_button.dart';

class ClientMenuPage extends StatefulWidget {
  const ClientMenuPage({super.key});

  @override
  State<ClientMenuPage> createState() => _ClientMenuPageState();
}

class _ClientMenuPageState extends State<ClientMenuPage> {
  static const Color burgundyColor = Color(0xFF6B1124);
  static const Color darkYellowColor = Color(0xFFD49A00);
  static const Color lightBgColor = Color(0xFFFAF6F0);

  String _selectedCategory = 'الكل';
  final Map<String, Map<String, dynamic>> _cart = {};

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  String _paymentMethod = 'نقداً عند الاستلام';
  String _whatsappNumber = '96594774950';

  @override
  void initState() {
    super.initState();
    _loadWhatsAppNumber();
  }

  Future<void> _loadWhatsAppNumber() async {
    try {
      final settingsDoc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('restaurant_info')
          .get();
      final savedNumber = settingsDoc.data()?['whatsappNumber'] as String?;
      if (savedNumber != null && savedNumber.trim().isNotEmpty && mounted) {
        setState(() => _whatsappNumber = savedNumber.trim());
      }
    } catch (e) {
      debugPrint('Error loading whatsapp number: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  double get _totalCartPrice {
    var total = 0.0;
    for (final item in _cart.values) {
      total += (item['price'] as num).toDouble() * (item['quantity'] as int);
    }
    return total;
  }

  int get _totalCartItems {
    var count = 0;
    for (final item in _cart.values) {
      count += item['quantity'] as int;
    }
    return count;
  }

  String _localizedItemName(String itemId, Map<String, dynamic> item) {
    return MenuItem.fromMap(
      itemId,
      item,
    ).localizedName(context.read<LocaleProvider>().localeCode);
  }

  String _localizedItemDescription(String itemId, Map<String, dynamic> item) {
    return MenuItem.fromMap(
      itemId,
      item,
    ).localizedDescription(context.read<LocaleProvider>().localeCode);
  }

  String _cartItemName(Map<String, dynamic> item) {
    final localeCode = context.read<LocaleProvider>().localeCode;
    if (localeCode.startsWith('en')) {
      final english = item['nameEn']?.toString().trim() ?? '';
      if (english.isNotEmpty) return english;
    } else {
      final arabic = item['nameAr']?.toString().trim() ?? '';
      if (arabic.isNotEmpty) return arabic;
    }
    return item['name']?.toString() ?? '';
  }

  void _addToCart(String itemId, Map<String, dynamic> itemData) {
    setState(() {
      if (_cart.containsKey(itemId)) {
        _cart[itemId]!['quantity'] = (_cart[itemId]!['quantity'] as int) + 1;
      } else {
        _cart[itemId] = {
          'name': itemData['name'],
          'nameAr': itemData['name_ar'] ?? itemData['nameAr'],
          'nameEn': itemData['name_en'] ?? itemData['nameEn'],
          'price': (itemData['price'] ?? 0.0).toDouble(),
          'quantity': 1,
        };
      }
    });
  }

  void _removeFromCart(String itemId) {
    setState(() {
      if (!_cart.containsKey(itemId)) return;
      if ((_cart[itemId]!['quantity'] as int) > 1) {
        _cart[itemId]!['quantity'] = (_cart[itemId]!['quantity'] as int) - 1;
      } else {
        _cart.remove(itemId);
      }
    });
  }

  void _showItemImageDialog({
    required String itemId,
    required Map<String, dynamic> item,
  }) {
    final imageUrl = item['imageUrl'] as String? ?? '';
    final strings = AppStrings.read(context);
    final name = _localizedItemName(itemId, item);
    final price = (item['price'] as num?)?.toDouble() ?? 0;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 40,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 260,
                        child: imageUrl.isNotEmpty
                            ? NetworkMenuImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    _buildImagePlaceholder(large: true),
                              )
                            : _buildImagePlaceholder(large: true),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => Navigator.pop(ctx),
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.close, color: burgundyColor),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                  child: Column(
                    children: [
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F1F1F),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${price.toStringAsFixed(3)} ${strings.currency}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: darkYellowColor,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: burgundyColor,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(
                                color: darkYellowColor,
                                width: 1.5,
                              ),
                            ),
                          ),
                          onPressed: () {
                            _addToCart(itemId, item);
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(strings.addedToCart(name)),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.add_shopping_cart,
                            color: darkYellowColor,
                          ),
                          label: Text(
                            strings.tr(
                              'إضافة إلى سلة المشتريات',
                              'Add to cart',
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _sendOrderToWhatsApp(
    String invoiceNumber,
    String orderTime,
  ) async {
    final strings = AppStrings.read(context);
    final itemsDetails = StringBuffer();
    for (final item in _cart.values) {
      final lineTotal =
          (item['price'] as num).toDouble() * (item['quantity'] as int);
      itemsDetails.writeln(
        "• ${_cartItemName(item)} x${item['quantity']} "
        "(${lineTotal.toStringAsFixed(3)} ${strings.currency})",
      );
    }

    final paymentLabel = _paymentMethod == 'نقداً عند الاستلام'
        ? strings.tr('نقداً عند الاستلام', 'Cash on delivery')
        : strings.tr('كي نت عند الاستلام', 'K-Net on delivery');
    final message = strings.isArabic
        ? '''
🧾 *فاتورة طلب جديدة - Molton Cookies*
----------------------------------
📌 *رقم الفاتورة:* #$invoiceNumber
👤 *اسم العميل:* ${_nameController.text.trim()}
📞 *رقم الهاتف:* ${_phoneController.text.trim()}
📍 *عنوان التوصيل:* ${_addressController.text.trim()}
💳 *طريقة الدفع:* $_paymentMethod

🕒 *وقت الطلب:* $orderTime

🛒 *تفاصيل الطلب:*
$itemsDetails
----------------------------------
💰 *الإجمالي النهائي:* ${_totalCartPrice.toStringAsFixed(3)} د.ك
----------------------------------
شكراً لطلبكم من مولتن كوكيز! ❤️
'''
        : '''
🧾 *New order invoice - Molton Cookies*
----------------------------------
📌 *Invoice number:* #$invoiceNumber
👤 *Customer name:* ${_nameController.text.trim()}
📞 *Phone number:* ${_phoneController.text.trim()}
📍 *Delivery address:* ${_addressController.text.trim()}
💳 *Payment method:* $paymentLabel

🕒 *Order time:* $orderTime

🛒 *Order details:*
$itemsDetails
----------------------------------
💰 *Grand total:* ${_totalCartPrice.toStringAsFixed(3)} KWD
----------------------------------
Thank you for ordering from Molton Cookies! ❤️
''';

    final opened = await openWhatsAppChat(
      phone: _whatsappNumber,
      message: message,
    );

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.tr('تعذر فتح الواتساب. افتح الرابط يدوياً:', 'Could not open WhatsApp. Open this link manually:')}\nhttps://wa.me/${normalizeWhatsAppNumber(_whatsappNumber)}',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    }

    return opened;
  }

  void _showWhatsAppFallbackDialog(String invoiceNumber) {
    final strings = AppStrings.read(context);
    final link = 'https://wa.me/${normalizeWhatsAppNumber(_whatsappNumber)}';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          strings.tr('فتح الواتساب يدوياً', 'Open WhatsApp manually'),
        ),
        content: SelectableText(
          '${strings.tr('لم يُفتح الواتساب تلقائياً.\nانسخ الرابط أو افتحه في تبويب جديد:', 'WhatsApp did not open automatically.\nCopy the link or open it in a new tab:')}\n\n$link',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(strings.tr('إغلاق', 'Close')),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await openWhatsAppChat(
                phone: _whatsappNumber,
                message: 'طلب Molton Cookies - فاتورة #$invoiceNumber',
              );
            },
            child: Text(strings.tr('إعادة المحاولة', 'Try again')),
          ),
        ],
      ),
    );
  }

  void _showCartBottomSheet() {
    final strings = AppStrings.read(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: lightBgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 20,
                left: 20,
                right: 20,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.85,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            strings.tr(
                              'تأكيد الطلب والفاتورة',
                              'Confirm order and invoice',
                            ),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: burgundyColor,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close, color: burgundyColor),
                          ),
                        ],
                      ),
                      const Divider(),
                      Expanded(
                        child: ListView(
                          children: [
                            Text(
                              strings.tr(
                                'الأصناف المختارة:',
                                'Selected items:',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ..._cart.entries.map((entry) {
                              final item = entry.value;
                              final lineTotal =
                                  (item['price'] as num).toDouble() *
                                  (item['quantity'] as int);
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "${_cartItemName(item)} (x${item['quantity']})",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      '${lineTotal.toStringAsFixed(3)} ${strings.currency}',
                                    ),
                                  ],
                                ),
                              );
                            }),
                            const Divider(height: 25),
                            Text(
                              strings.tr(
                                'بيانات التوصيل:',
                                'Delivery details:',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: burgundyColor,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                labelText: strings.customerName,
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (val) => val == null || val.isEmpty
                                  ? strings.tr(
                                      'يرجى إدخال الاسم',
                                      'Please enter your name',
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: strings.phone,
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (val) => val == null || val.isEmpty
                                  ? strings.tr(
                                      'يرجى إدخال رقم الهاتف',
                                      'Please enter your phone number',
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _addressController,
                              maxLines: 2,
                              decoration: InputDecoration(
                                labelText: strings.tr(
                                  'عنوان التوصيل (المنطقة، القطعة، الشارع، المنزل)',
                                  'Delivery address (area, block, street, house)',
                                ),
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (val) => val == null || val.isEmpty
                                  ? strings.tr(
                                      'يرجى إدخال العنوان',
                                      'Please enter the address',
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 15),
                            Text(
                              '${strings.paymentMethod}:',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: burgundyColor,
                              ),
                            ),
                            RadioGroup<String>(
                              groupValue: _paymentMethod,
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() => _paymentMethod = val);
                                }
                              },
                              child: Column(
                                children: [
                                  RadioListTile<String>(
                                    title: Text(
                                      strings.tr(
                                        'دفع نقدي عند الاستلام (كاش)',
                                        'Cash on delivery',
                                      ),
                                    ),
                                    value: 'نقداً عند الاستلام',
                                    activeColor: burgundyColor,
                                  ),
                                  RadioListTile<String>(
                                    title: Text(
                                      strings.tr(
                                        'كي نت (K-Net) عند الاستلام',
                                        'K-Net on delivery',
                                      ),
                                    ),
                                    value: 'K-Net (كي نت)',
                                    activeColor: burgundyColor,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${strings.grandTotal}:',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_totalCartPrice.toStringAsFixed(3)} ${strings.currency}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: darkYellowColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.send, color: Colors.white),
                          label: Text(
                            strings.tr(
                              'إرسال الطلب عبر الواتساب',
                              'Send order via WhatsApp',
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: _cart.isEmpty
                              ? null
                              : () async {
                                  if (!_formKey.currentState!.validate()) {
                                    return;
                                  }

                                  final now = DateTime.now();
                                  final orderTimeStr =
                                      '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
                                  final invoiceNumber =
                                      (10000 + Random().nextInt(90000))
                                          .toString();

                                  final orderItems = _cart.entries
                                      .map(
                                        (entry) => {
                                          'menuItemId': entry.key,
                                          'name': entry.value['name'],
                                          'unitPrice': entry.value['price'],
                                          'quantity': entry.value['quantity'],
                                          'selectedOptions': <dynamic>[],
                                        },
                                      )
                                      .toList();

                                  try {
                                    final order = Order(
                                      id: '',
                                      customerName: _nameController.text.trim(),
                                      phone: _phoneController.text.trim(),
                                      address: _addressController.text.trim(),
                                      items: orderItems
                                          .map(
                                            (item) => OrderLineItem.fromMap(
                                              Map<String, dynamic>.from(item),
                                            ),
                                          )
                                          .toList(),
                                      totalPrice: _totalCartPrice,
                                      orderType: OrderType.delivery,
                                      status: OrderStatus.pending,
                                      createdAt: DateTime.now(),
                                      invoiceNumber: invoiceNumber,
                                      paymentMethod: _paymentMethod,
                                      orderSource: 'customer_web',
                                    );
                                    final created = await ApiService.instance
                                        .createOrder(order);
                                    await OrdersDemoService.registerOrder(
                                      created,
                                    );
                                  } catch (e) {
                                    debugPrint('Order save error: $e');
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            strings.tr(
                                              'تعذر حفظ الطلب. حاول مرة أخرى.',
                                              'Could not save the order. Please try again.',
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                    return;
                                  }

                                  final opened = await _sendOrderToWhatsApp(
                                    invoiceNumber,
                                    orderTimeStr,
                                  );

                                  if (!opened && context.mounted) {
                                    _showWhatsAppFallbackDialog(invoiceNumber);
                                  }

                                  setState(_cart.clear);
                                  _nameController.clear();
                                  _phoneController.clear();
                                  _addressController.clear();

                                  if (context.mounted) {
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          strings.tr(
                                            'تم إرسال طلبك بنجاح!',
                                            'Your order was sent successfully!',
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                },
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCategoryBar(Map<String, String> categories) {
    return Container(
      height: 60,
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories.keys.elementAt(index);
          final isSelected = category == _selectedCategory;

          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: ChoiceChip(
              label: Text(
                categories[category] ?? category,
                style: TextStyle(
                  color: isSelected ? Colors.white : burgundyColor,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              selected: isSelected,
              selectedColor: burgundyColor,
              backgroundColor: const Color(0xFFF4ECE9),
              side: BorderSide(
                color: isSelected ? darkYellowColor : Colors.transparent,
                width: 1.5,
              ),
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedCategory = category);
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildMenuItemCard({
    required String itemId,
    required Map<String, dynamic> item,
    required int quantity,
  }) {
    final strings = AppStrings.of(context);
    final imageUrl = item['imageUrl'] as String? ?? '';
    final price = (item['price'] as num?)?.toDouble() ?? 0;
    final name = _localizedItemName(itemId, item);
    final description = _localizedItemDescription(itemId, item);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: burgundyColor.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: burgundyColor.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showItemImageDialog(itemId: itemId, item: item),
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: imageUrl.isNotEmpty
                          ? NetworkMenuImage(
                              imageUrl: imageUrl,
                              width: 85,
                              height: 85,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return _buildImagePlaceholder();
                              },
                            )
                          : _buildImagePlaceholder(),
                    ),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.zoom_in,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F1F1F),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF757575),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${price.toStringAsFixed(3)} ${strings.currency}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: darkYellowColor,
                    ),
                  ),
                ],
              ),
            ),
            quantity == 0
                ? InkWell(
                    onTap: () => _addToCart(itemId, item),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: burgundyColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add,
                        color: darkYellowColor,
                        size: 20,
                      ),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4ECE9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: darkYellowColor.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.remove,
                            size: 16,
                            color: burgundyColor,
                          ),
                          onPressed: () => _removeFromCart(itemId),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                        ),
                        Text(
                          '$quantity',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: burgundyColor,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.add,
                            size: 16,
                            color: burgundyColor,
                          ),
                          onPressed: () => _addToCart(itemId, item),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                        ),
                      ],
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder({bool large = false}) {
    final size = large ? 260.0 : 85.0;
    final iconSize = large ? 80.0 : 38.0;

    return Container(
      width: large ? double.infinity : size,
      height: size,
      color: const Color(0xFFF4ECE9),
      child: Icon(Icons.cookie, color: burgundyColor, size: iconSize),
    );
  }

  Widget _buildFloatingCartBar() {
    final strings = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: burgundyColor,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
              side: const BorderSide(color: darkYellowColor, width: 1.5),
            ),
          ),
          onPressed: _showCartBottomSheet,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: darkYellowColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  strings.tr(
                    '$_totalCartItems أصناف',
                    '$_totalCartItems items',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                strings.continueOrder,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                '${_totalCartPrice.toStringAsFixed(3)} ${strings.currency}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: darkYellowColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Directionality(
      textDirection: context.watch<LocaleProvider>().textDirection,
      child: Scaffold(
        backgroundColor: lightBgColor,
        appBar: AppBar(
          backgroundColor: burgundyColor,
          elevation: 2,
          centerTitle: true,
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cookie, color: darkYellowColor, size: 26),
              SizedBox(width: 8),
              Text(
                'Molten Cookies',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          actions: [
            const LanguageToggleButton(
              compact: true,
              foregroundColor: Colors.white,
            ),
            IconButton(
              icon: const Icon(Icons.admin_panel_settings, color: Colors.white),
              onPressed: () => Navigator.pushNamed(context, '/admin'),
            ),
          ],
        ),
        body: Column(
          children: [
            StreamBuilder<List<MenuItemRecord>>(
              stream: MenuStorageService.instance.watchItems(),
              builder: (context, snapshot) {
                final categories = <String, String>{'الكل': strings.all};
                final records = snapshot.data ?? [];
                for (final record in records) {
                  final data = record.data;
                  if (data['isAvailable'] == false) continue;
                  if (data['showOnWebsite'] == false ||
                      data['show_on_website'] == false) {
                    continue;
                  }
                  final cat = data['categoryName'];
                  if (cat != null && cat.toString().isNotEmpty) {
                    final rawCategory = cat.toString();
                    final item = MenuItem.fromMap(record.id, data);
                    categories[rawCategory] = item.localizedCategoryName(
                      strings.localeCode,
                    );
                  }
                }

                return _buildCategoryBar(categories);
              },
            ),
            Expanded(
              child: StreamBuilder<List<MenuItemRecord>>(
                stream: MenuStorageService.instance.watchItems(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        '${strings.tr('خطأ', 'Error')}: ${snapshot.error}',
                      ),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: burgundyColor),
                    );
                  }

                  final records = snapshot.data ?? [];
                  final filteredRecords = records.where((record) {
                    final data = record.data;
                    if (data['isAvailable'] == false) return false;
                    if (data['showOnWebsite'] == false ||
                        data['show_on_website'] == false) {
                      return false;
                    }
                    if (_selectedCategory == 'الكل') return true;
                    return data['categoryName'] == _selectedCategory;
                  }).toList();

                  if (filteredRecords.isEmpty) {
                    return Center(child: Text(strings.noItemsAvailable));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    itemCount: filteredRecords.length,
                    itemBuilder: (context, index) {
                      final record = filteredRecords[index];
                      final data = record.data;
                      final id = record.id;
                      final qtyInCart = _cart[id]?['quantity'] as int? ?? 0;

                      return _buildMenuItemCard(
                        itemId: id,
                        item: data,
                        quantity: qtyInCart,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
        bottomNavigationBar: _totalCartItems > 0
            ? _buildFloatingCartBar()
            : null,
      ),
    );
  }
}
