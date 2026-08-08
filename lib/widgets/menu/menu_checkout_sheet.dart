import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/kuwait_governorates.dart';
import '../../l10n/app_strings.dart';
import '../../models/customer_restaurant_context.dart';
import '../../models/delivery_address_details.dart';
import '../../models/delivery_zone.dart';
import '../../providers/cart_provider.dart';
import '../../providers/locale_provider.dart';
import '../../services/api_service.dart';
import '../../services/orders_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/whatsapp_launcher.dart';
import '../../utils/whatsapp_order_message.dart';

class MenuCheckoutSheet extends StatefulWidget {
  const MenuCheckoutSheet({super.key, this.restaurantContext});

  final CustomerRestaurantContext? restaurantContext;

  static Future<void> show(
    BuildContext context, {
    CustomerRestaurantContext? restaurantContext,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.brandSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => MenuCheckoutSheet(restaurantContext: restaurantContext),
    );
  }

  @override
  State<MenuCheckoutSheet> createState() => _MenuCheckoutSheetState();
}

class _MenuCheckoutSheetState extends State<MenuCheckoutSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _blockController = TextEditingController();
  final _streetController = TextEditingController();
  final _avenueController = TextEditingController();
  final _houseController = TextEditingController();
  final _floorController = TextEditingController();

  var _paymentMethod = 'كاش';
  var _submitting = false;
  var _loadingZones = true;

  List<DeliveryZone> _zones = [];
  String? _selectedGovernorate;
  DeliveryZone? _selectedZone;

  static const _defaultWhatsappNumber = '96594774950';

  String get _restaurantName =>
      widget.restaurantContext?.name ?? 'Molten Cookies';

  String get _whatsappNumber =>
      widget.restaurantContext?.whatsappNumber ?? _defaultWhatsappNumber;

  String get _restaurantId =>
      widget.restaurantContext?.id ?? ApiService.defaultRestaurantId;

  String? get _restaurantSlug => widget.restaurantContext?.slug;

  double get _deliveryFee => _selectedZone?.deliveryFee ?? 0;

  List<String> get _availableGovernorates {
    if (_zones.isEmpty) return kuwaitGovernorates;
    final fromZones = _zones.map((zone) => zone.governorate).toSet().toList()
      ..sort();
    return fromZones;
  }

  List<DeliveryZone> get _areasForGovernorate {
    if (_selectedGovernorate == null) return const [];
    return _zones
        .where((zone) => zone.governorate == _selectedGovernorate)
        .toList()
      ..sort((a, b) => a.areaName.compareTo(b.areaName));
  }

  DeliveryAddressDetails get _addressDetails => DeliveryAddressDetails(
        block: _blockController.text.trim(),
        street: _streetController.text.trim(),
        avenue: _avenueController.text.trim(),
        houseNumber: _houseController.text.trim(),
        floorApartment: _floorController.text.trim(),
      );

  String _formattedAddressArabic() {
    final governorate = _selectedZone?.governorate ?? _selectedGovernorate ?? '';
    final areaName = _selectedZone?.areaName ?? '';
    return _addressDetails.formatArabic(
      governorate: governorate,
      areaName: areaName,
    );
  }

  String _formattedAddressEnglish() {
    final governorate = _selectedZone?.governorate ?? _selectedGovernorate ?? '';
    final areaName = _selectedZone?.areaName ?? '';
    return _addressDetails.formatEnglish(
      governorate: governorate,
      areaName: areaName,
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadDeliveryZones());
  }

  Future<void> _loadDeliveryZones() async {
    try {
      final zones = await ApiService.instance.fetchDeliveryZones(
        slug: _restaurantSlug,
        restaurantId: _restaurantId,
      );
      if (!mounted) return;
      setState(() {
        _zones = zones;
        _loadingZones = false;
        if (_availableGovernorates.isNotEmpty) {
          _selectedGovernorate ??= _availableGovernorates.first;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingZones = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _blockController.dispose();
    _streetController.dispose();
    _avenueController.dispose();
    _houseController.dispose();
    _floorController.dispose();
    super.dispose();
  }

  Future<void> _submit(CartProvider cart, AppStrings strings) async {
    if (!_formKey.currentState!.validate()) return;
    if (_zones.isNotEmpty && _selectedZone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.selectGovernorateAndArea)),
      );
      return;
    }

    setState(() => _submitting = true);

    final subtotal = cart.totalPrice;
    final grandTotal = subtotal + _deliveryFee;
    final invoiceNumber =
        DateTime.now().millisecondsSinceEpoch.toString().substring(5);
    final now = DateTime.now();
    final orderTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final addressArabic = _formattedAddressArabic();
    final addressEnglish = _formattedAddressEnglish();

    final message = WhatsAppOrderMessage.build(
      restaurantName: _restaurantName,
      invoiceNumber: invoiceNumber,
      customerName: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      paymentMethod: _paymentMethod,
      orderTime: orderTime,
      cartItems: cart.items,
      subtotal: subtotal,
      deliveryFee: _deliveryFee,
      grandTotal: grandTotal,
      addressArabic: addressArabic,
      addressEnglish: addressEnglish,
    );

    final opened = await openWhatsAppChat(
      phone: _whatsappNumber,
      message: message,
    );

    if (opened) {
      try {
        await OrdersService.instance.submitOrderFromCart(
          cartItems: List.from(cart.items),
          customerName: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          address: addressArabic,
          paymentMethod: _paymentMethod,
          invoiceNumber: invoiceNumber,
          restaurantId: _restaurantId,
          deliveryFee: _deliveryFee,
          governorate: _selectedZone?.governorate ?? _selectedGovernorate,
          areaName: _selectedZone?.areaName,
          deliveryZoneId: _selectedZone?.id,
          addressDetails: _addressDetails,
        );
      } catch (error) {
        debugPrint('Order backend sync failed: $error');
      }
    }

    if (!mounted) return;

    setState(() => _submitting = false);

    if (opened) {
      cart.clear();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.orderSentViaWhatsapp)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.whatsappOpenFailed(_whatsappNumber))),
      );
    }
  }

  Widget _buildTotals(CartProvider cart, AppStrings strings) {
    final subtotal = cart.totalPrice;
    final grandTotal = subtotal + _deliveryFee;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          _TotalRow(
            label: strings.subtotal,
            value: subtotal,
            currency: strings.currency,
          ),
          const SizedBox(height: 6),
          _TotalRow(
            label: strings.deliveryFee,
            value: _deliveryFee,
            currency: strings.currency,
            highlight: _selectedZone != null,
          ),
          const Divider(height: 20),
          _TotalRow(
            label: strings.grandTotal,
            value: grandTotal,
            currency: strings.currency,
            isBold: true,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final locale = context.watch<LocaleProvider>();
    final strings = AppStrings(locale.localeCode);
    final grandTotal = cart.totalPrice + _deliveryFee;

    return Directionality(
      textDirection: locale.textDirection,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.92,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.checkoutTitle,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.brandMaroon,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: locale.isArabic ? 'English' : 'العربية',
                        onPressed: () => context.read<LocaleProvider>().toggle(),
                        icon: Text(
                          locale.isArabic ? 'EN' : 'ع',
                          style: const TextStyle(
                            color: AppTheme.brandOrange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      ...cart.items.map(
                        (item) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            item.menuItem.localizedName(locale.localeCode),
                          ),
                          subtitle: Text(
                            '${item.unitPrice.toStringAsFixed(3)} ${strings.currency}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () => cart.updateQuantity(
                                  item.id,
                                  item.quantity - 1,
                                ),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              Text('${item.quantity}'),
                              IconButton(
                                onPressed: () => cart.updateQuantity(
                                  item.id,
                                  item.quantity + 1,
                                ),
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 32),
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: strings.customerName,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) => value == null || value.trim().isEmpty
                            ? strings.required
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: strings.phone,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) => value == null || value.trim().isEmpty
                            ? strings.required
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        strings.deliveryAddress,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.brandMaroon,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_loadingZones)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: LinearProgressIndicator(),
                        )
                      else ...[
                        DropdownButtonFormField<String>(
                          initialValue: _selectedGovernorate,
                          decoration: InputDecoration(
                            labelText: strings.governorate,
                            border: const OutlineInputBorder(),
                          ),
                          items: _availableGovernorates
                              .map(
                                (gov) => DropdownMenuItem(
                                  value: gov,
                                  child: Text(gov),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedGovernorate = value;
                              _selectedZone = null;
                            });
                          },
                          validator: (value) {
                            if (_zones.isEmpty) return null;
                            return value == null || value.isEmpty
                                ? strings.required
                                : null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedZone?.id,
                          decoration: InputDecoration(
                            labelText: strings.area,
                            border: const OutlineInputBorder(),
                            helperText: _areasForGovernorate.isEmpty &&
                                    _selectedGovernorate != null
                                ? strings.noAreasForGovernorate
                                : null,
                          ),
                          items: _areasForGovernorate
                              .map(
                                (zone) => DropdownMenuItem(
                                  value: zone.id,
                                  child: Text(
                                    '${zone.areaName} (${zone.deliveryFee.toStringAsFixed(3)} ${strings.currency})',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _areasForGovernorate.isEmpty
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedZone =
                                        _areasForGovernorate.firstWhere(
                                      (zone) => zone.id == value,
                                    );
                                  });
                                },
                          validator: (value) {
                            if (_zones.isEmpty) return null;
                            return value == null || value.isEmpty
                                ? strings.required
                                : null;
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _blockController,
                        decoration: InputDecoration(
                          labelText: strings.block,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) => value == null || value.trim().isEmpty
                            ? strings.required
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _streetController,
                        decoration: InputDecoration(
                          labelText: strings.street,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) => value == null || value.trim().isEmpty
                            ? strings.required
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _avenueController,
                        decoration: InputDecoration(
                          labelText: strings.avenue,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _houseController,
                        decoration: InputDecoration(
                          labelText: strings.houseNumber,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) => value == null || value.trim().isEmpty
                            ? strings.required
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _floorController,
                        decoration: InputDecoration(
                          labelText: strings.floorApartment,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _paymentMethod,
                        decoration: InputDecoration(
                          labelText: strings.paymentMethod,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'كاش',
                            child: Text(strings.cash),
                          ),
                          DropdownMenuItem(
                            value: 'K-Net',
                            child: Text(strings.knet),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _paymentMethod = value);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildTotals(cart, strings),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.brandMaroon,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: _submitting ? null : () => _submit(cart, strings),
                    child: _submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            strings.sendOrder(grandTotal.toStringAsFixed(3)),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    required this.currency,
    this.isBold = false,
    this.highlight = false,
  });

  final String label;
  final double value;
  final String currency;
  final bool isBold;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: highlight ? AppTheme.brandMaroon : Colors.black87,
            ),
          ),
        ),
        Text(
          '${value.toStringAsFixed(3)} $currency',
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: isBold ? AppTheme.brandMaroon : Colors.black87,
          ),
        ),
      ],
    );
  }
}
