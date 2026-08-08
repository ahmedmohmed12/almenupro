import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/menu_storage_service.dart';
import '../utils/whatsapp_launcher.dart';
import '../widgets/network_menu_image.dart';

class ClientMenuPage extends StatefulWidget {
  const ClientMenuPage({Key? key}) : super(key: key);

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

  void _addToCart(String itemId, Map<String, dynamic> itemData) {
    setState(() {
      if (_cart.containsKey(itemId)) {
        _cart[itemId]!['quantity'] = (_cart[itemId]!['quantity'] as int) + 1;
      } else {
        _cart[itemId] = {
          'name': itemData['name'],
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
    final name = item['name'] as String? ?? '';
    final price = (item['price'] as num?)?.toDouble() ?? 0;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
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
                                errorBuilder: (_, __, ___) =>
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
                        '${price.toStringAsFixed(3)} د.ك',
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
                                content: Text('تمت إضافة "$name" إلى السلة'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.add_shopping_cart,
                            color: darkYellowColor,
                          ),
                          label: const Text(
                            'إضافة إلى سلة المشتريات',
                            style: TextStyle(
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
    final itemsDetails = StringBuffer();
    for (final item in _cart.values) {
      final lineTotal =
          (item['price'] as num).toDouble() * (item['quantity'] as int);
      itemsDetails.writeln(
        "• ${item['name']} x${item['quantity']} (${lineTotal.toStringAsFixed(3)} د.ك)",
      );
    }

    final message = '''
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
''';

    final opened = await openWhatsAppChat(
      phone: _whatsappNumber,
      message: message,
    );

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر فتح الواتساب. افتح الرابط يدوياً:\n'
            'https://wa.me/${normalizeWhatsAppNumber(_whatsappNumber)}',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    }

    return opened;
  }

  void _showWhatsAppFallbackDialog(String invoiceNumber) {
    final link = 'https://wa.me/${normalizeWhatsAppNumber(_whatsappNumber)}';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('فتح الواتساب يدوياً'),
        content: SelectableText(
          'لم يُفتح الواتساب تلقائياً.\n'
          'انسخ الرابط أو افتحه في تبويب جديد:\n\n$link',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await openWhatsAppChat(
                phone: _whatsappNumber,
                message: 'طلب Molton Cookies - فاتورة #$invoiceNumber',
              );
            },
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  void _showCartBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'تأكيد الطلب والفاتورة',
                            style: TextStyle(
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
                            const Text(
                              'الأصناف المختارة:',
                              style: TextStyle(
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "${item['name']} (x${item['quantity']})",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text('${lineTotal.toStringAsFixed(3)} د.ك'),
                                  ],
                                ),
                              );
                            }),
                            const Divider(height: 25),
                            const Text(
                              'بيانات التوصيل:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: burgundyColor,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'اسم العميل',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (val) => val == null || val.isEmpty
                                  ? 'يرجى إدخال الاسم'
                                  : null,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'رقم الهاتف',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (val) => val == null || val.isEmpty
                                  ? 'يرجى إدخال رقم الهاتف'
                                  : null,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _addressController,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText:
                                    'عنوان التوصيل (المنطقة، القطعة، الشارع، المنزل)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (val) => val == null || val.isEmpty
                                  ? 'يرجى إدخال العنوان'
                                  : null,
                            ),
                            const SizedBox(height: 15),
                            const Text(
                              'طريقة الدفع:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: burgundyColor,
                              ),
                            ),
                            RadioListTile<String>(
                              title: const Text('دفع نقدي عند الاستلام (كاش)'),
                              value: 'نقداً عند الاستلام',
                              groupValue: _paymentMethod,
                              activeColor: burgundyColor,
                              onChanged: (val) =>
                                  setModalState(() => _paymentMethod = val!),
                            ),
                            RadioListTile<String>(
                              title: const Text('كي نت (K-Net) عند الاستلام'),
                              value: 'K-Net (كي نت)',
                              groupValue: _paymentMethod,
                              activeColor: burgundyColor,
                              onChanged: (val) =>
                                  setModalState(() => _paymentMethod = val!),
                            ),
                          ],
                        ),
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'الإجمالي النهائي:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_totalCartPrice.toStringAsFixed(3)} د.ك',
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
                          label: const Text(
                            'إرسال الطلب عبر الواتساب',
                            style: TextStyle(
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
                                    await FirebaseFirestore.instance
                                        .collection('orders')
                                        .add({
                                      'invoiceNumber': invoiceNumber,
                                      'customerName':
                                          _nameController.text.trim(),
                                      'phone': _phoneController.text.trim(),
                                      'address':
                                          _addressController.text.trim(),
                                      'paymentMethod': _paymentMethod,
                                      'orderType': 'delivery',
                                      'items': orderItems,
                                      'totalPrice': _totalCartPrice,
                                      'status': 'pending',
                                      'createdAt':
                                          FieldValue.serverTimestamp(),
                                    });
                                  } catch (e) {
                                    debugPrint('Order save error: $e');
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'تعذر حفظ الطلب. حاول مرة أخرى.',
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
                                      const SnackBar(
                                        content: Text('تم إرسال طلبك بنجاح!'),
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

  Widget _buildCategoryBar(List<String> categories) {
    return Container(
      height: 60,
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = category == _selectedCategory;

          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: ChoiceChip(
              label: Text(
                category,
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
    final imageUrl = item['imageUrl'] as String? ?? '';
    final price = (item['price'] as num?)?.toDouble() ?? 0;

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
                    item['name'] as String? ?? '',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F1F1F),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item['description'] as String? ?? '',
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
                    '${price.toStringAsFixed(3)} د.ك',
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: darkYellowColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_totalCartItems أصناف',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Text(
                'متابعة الطلب',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                '${_totalCartPrice.toStringAsFixed(3)} د.ك',
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
    return Scaffold(
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
              final categories = <String>{'الكل'};
              final records = snapshot.data ?? [];
              for (final record in records) {
                final data = record.data;
                if (data['isAvailable'] == false) continue;
                final cat = data['categoryName'];
                if (cat != null && cat.toString().isNotEmpty) {
                  categories.add(cat.toString());
                }
              }

              return _buildCategoryBar(categories.toList());
            },
          ),
          Expanded(
            child: StreamBuilder<List<MenuItemRecord>>(
              stream: MenuStorageService.instance.watchItems(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('خطأ: ${snapshot.error}'));
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
                  if (_selectedCategory == 'الكل') return true;
                  return data['categoryName'] == _selectedCategory;
                }).toList();

                if (filteredRecords.isEmpty) {
                  return const Center(child: Text('لا توجد أصناف حالياً'));
                }

                return ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
      bottomNavigationBar:
          _totalCartItems > 0 ? _buildFloatingCartBar() : null,
    );
  }
}
