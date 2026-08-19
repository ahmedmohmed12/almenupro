import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/kuwait_governorates.dart';
import '../../l10n/app_strings.dart';
import '../../models/customer_restaurant_context.dart';
import '../../models/delivery_address_details.dart';
import '../../models/delivery_zone.dart';
import '../../models/payment_method_config.dart';
import '../../providers/cart_provider.dart';
import '../../providers/customer_session_provider.dart';
import '../../providers/locale_provider.dart';
import '../../services/api_service.dart';
import '../../services/orders_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/whatsapp_launcher.dart';
import '../../utils/whatsapp_order_message.dart';
import '../pos/smart_salesman_widget.dart';

class MenuCheckoutSheet extends StatefulWidget {
  const MenuCheckoutSheet({super.key, this.restaurantContext});

  final CustomerRestaurantContext? restaurantContext;

  static Future<void> show(
    BuildContext context, {
    CustomerRestaurantContext? restaurantContext,
  }) {
    final cart = context.read<CartProvider>();
    final locale = context.read<LocaleProvider>();
    final session = context.read<CustomerSessionProvider>();
    final wide = MediaQuery.sizeOf(context).width >= 768;
    final sheet = MultiProvider(
      providers: [
        ChangeNotifierProvider<CartProvider>.value(value: cart),
        ChangeNotifierProvider<LocaleProvider>.value(value: locale),
        ChangeNotifierProvider<CustomerSessionProvider>.value(value: session),
      ],
      child: MenuCheckoutSheet(restaurantContext: restaurantContext),
    );

    if (wide) {
      return showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: AppTheme.brandSurface,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820, maxHeight: 880),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: sheet,
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.brandSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => sheet,
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
  var _checkoutStep = 1;
  var _applyWallet = false;

  List<DeliveryZone> _zones = [];
  List<PaymentMethodConfig> _paymentMethods = PaymentMethodConfig.defaults()
      .where((method) => method.enabled)
      .toList();
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

  CustomerSessionProvider get _session =>
      context.read<CustomerSessionProvider>();

  double _walletAvailable() => _session.walletBalance;

  double _walletRedeemable(double subtotal) {
    final due = subtotal + _deliveryFee;
    final available = _walletAvailable();
    if (!_applyWallet || available <= 0 || due <= 0) return 0;
    return available < due ? available : due;
  }

  double _grandTotal(double subtotal) =>
      (subtotal + _deliveryFee - _walletRedeemable(subtotal)).clamp(0, double.infinity);

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
    unawaited(_loadPaymentMethods());
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillFromSession());
  }

  void _prefillFromSession() {
    if (!mounted) return;
    final session = context.read<CustomerSessionProvider>();
    if (_phoneController.text.trim().isEmpty && session.phone.isNotEmpty) {
      _phoneController.text = session.phone;
    }
    final profile = session.profile;
    if (profile == null) return;
    if (_nameController.text.trim().isEmpty && profile.customerName.isNotEmpty) {
      _nameController.text = profile.customerName;
    }
    if (profile.governorate.isNotEmpty) {
      _selectedGovernorate ??= profile.governorate;
    }
    if (profile.paymentMethod.isNotEmpty) {
      _paymentMethod = profile.paymentMethod;
    }
    final details = profile.addressDetails;
    if (_blockController.text.isEmpty) _blockController.text = details.block;
    if (_streetController.text.isEmpty) _streetController.text = details.street;
    if (_avenueController.text.isEmpty) _avenueController.text = details.avenue;
    if (_houseController.text.isEmpty) _houseController.text = details.houseNumber;
    if (_floorController.text.isEmpty) {
      _floorController.text = details.floorApartment;
    }
    setState(() {});
  }

  Future<void> _loadPaymentMethods() async {
    try {
      final settings = await ApiService.instance.fetchSettings(
        restaurantId: _restaurantId,
      );
      if (!mounted) return;
      final methods = settings.configuredPaymentMethods
          .where((method) => method.id != 'wallet')
          .toList();
      setState(() {
        if (methods.isNotEmpty) _paymentMethods = methods;
        if (!_paymentMethods.any((method) => method.storageValue == _paymentMethod)) {
          _paymentMethod = _paymentMethods.first.storageValue;
        }
      });
    } catch (_) {}
  }

  Future<void> _loadDeliveryZones() async {
    try {
      final zones = await ApiService.instance.fetchDeliveryZones(
        slug: _restaurantSlug,
        restaurantId: _restaurantId,
      );
      if (!mounted) return;
      setState(() {
        _zones = zones.where((zone) => zone.id.isNotEmpty).toList();
        _loadingZones = false;
        if (_availableGovernorates.isNotEmpty) {
          _selectedGovernorate ??= _availableGovernorates.first;
        }
        if (_selectedGovernorate != null &&
            !_availableGovernorates.contains(_selectedGovernorate)) {
          _selectedGovernorate = _availableGovernorates.first;
          _selectedZone = null;
        }
        final profile = context.read<CustomerSessionProvider>().profile;
        if (profile != null && profile.deliveryZoneId != null) {
          final match = _zones.where((zone) => zone.id == profile.deliveryZoneId);
          if (match.isNotEmpty) {
            _selectedZone = match.first;
            _selectedGovernorate = match.first.governorate;
          }
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
    final walletRedeem = _walletRedeemable(subtotal);
    final grandTotal = _grandTotal(subtotal);
    final invoiceNumber =
        DateTime.now().millisecondsSinceEpoch.toString().substring(5);
    final now = DateTime.now();
    final orderTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final addressArabic = _formattedAddressArabic();
    final addressEnglish = _formattedAddressEnglish();

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
        orderSource: 'customer_web',
        walletRedeemAmount: walletRedeem > 0 ? walletRedeem : null,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ الطلب: $error')),
      );
      return;
    }

    if (!mounted) return;
    if (walletRedeem > 0) {
      context.read<CustomerSessionProvider>().applyWalletDebit(walletRedeem);
    }

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
    unawaited(openWhatsAppChat(phone: _whatsappNumber, message: message));

    if (!mounted) return;

    setState(() => _submitting = false);
    cart.clear();
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.orderSentViaWhatsapp)),
    );
  }

  Widget _buildTotals(CartProvider cart, AppStrings strings) {
    final subtotal = cart.totalPrice;
    final wallet = _walletRedeemable(subtotal);
    final grandTotal = _grandTotal(subtotal);

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
          if (wallet > 0) ...[
            const SizedBox(height: 6),
            _TotalRow(
              label: strings.isArabic ? 'خصم المحفظة' : 'Wallet',
              value: -wallet,
              currency: strings.currency,
              highlight: true,
            ),
          ],
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

  Widget _stepIndicator(AppStrings strings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 420;
          return Row(
            children: [
              Flexible(
                child: _StepChip(
                  number: '1',
                  label: compact
                      ? (strings.isArabic ? 'السلة' : 'Cart')
                      : (strings.isArabic ? 'السلة والعروض' : 'Cart'),
                  active: _checkoutStep == 1,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(child: Divider()),
              const SizedBox(width: 8),
              Flexible(
                child: _StepChip(
                  number: '2',
                  label: compact
                      ? (strings.isArabic ? 'الدفع' : 'Pay')
                      : (strings.isArabic ? 'التفاصيل والدفع' : 'Details'),
                  active: _checkoutStep == 2,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final locale = context.watch<LocaleProvider>();
    final session = context.watch<CustomerSessionProvider>();
    final strings = AppStrings(locale.localeCode);
    final grandTotal = _grandTotal(cart.totalPrice);

    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 768;
    final compact = size.width < 420;
    final sheetHeight = wide ? size.height : size.height * (size.height < 700 ? 0.96 : 0.92);

    return Directionality(
      textDirection: locale.textDirection,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Material(
          color: AppTheme.brandSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight.isFinite &&
                      constraints.maxHeight < size.height
                  ? constraints.maxHeight
                  : sheetHeight;
              return SizedBox(
                width: double.infinity,
                height: height,
                child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(compact ? 12 : 20, 12, 8, 0),
                    child: Row(
                      children: [
                        if (_checkoutStep == 2)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => _checkoutStep = 1),
                            icon: const Icon(Icons.arrow_back),
                          ),
                        Expanded(
                          child: Text(
                            _checkoutStep == 1
                                ? (strings.isArabic
                                    ? 'سلتك — البياع الشاطر'
                                    : 'Cart & suggestions')
                                : strings.checkoutTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compact ? 16 : 20,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.brandMaroon,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: locale.isArabic ? 'English' : 'العربية',
                          onPressed: () =>
                              context.read<LocaleProvider>().toggle(),
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
                  _stepIndicator(strings),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 12 : 20,
                      ),
                      children: [
                        if (_checkoutStep == 1) ...[
                          if (cart.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                locale.isArabic
                                    ? 'السلة فارغة'
                                    : 'Your cart is empty',
                              ),
                            ),
                          ...cart.items.map(
                            (item) => _CartLine(
                              name: item.menuItem
                                  .localizedName(locale.localeCode),
                              priceLabel:
                                  '${item.unitPrice.toStringAsFixed(3)} ${strings.currency}',
                              quantity: item.quantity,
                              onDecrease: () => cart.updateQuantity(
                                item.id,
                                item.quantity - 1,
                              ),
                              onIncrease: () => cart.updateQuantity(
                                item.id,
                                item.quantity + 1,
                              ),
                            ),
                          ),
                          if (!cart.isEmpty)
                            SmartSalesmanWidget(
                              cartItems: cart.items,
                              cartTotal: cart.totalPrice,
                              restaurantId: _restaurantId,
                              onAddItem: (item) => cart.addMenuItem(item),
                            ),
                          const SizedBox(height: 12),
                          _buildTotals(cart, strings),
                          const SizedBox(height: 12),
                        ] else ...[
                          _ResponsivePair(
                            first: TextFormField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                labelText: strings.customerName,
                                isDense: compact,
                                border: const OutlineInputBorder(),
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? strings.required
                                      : null,
                            ),
                            second: TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: strings.phone,
                                isDense: compact,
                                border: const OutlineInputBorder(),
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? strings.required
                                      : null,
                            ),
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
                          else
                            _ResponsivePair(
                              first: DropdownButtonFormField<String>(
                                key: ValueKey(
                                  'gov-$_selectedGovernorate-${_availableGovernorates.length}',
                                ),
                                isExpanded: true,
                                initialValue: _availableGovernorates
                                        .contains(_selectedGovernorate)
                                    ? _selectedGovernorate
                                    : null,
                                decoration: InputDecoration(
                                  labelText: strings.governorate,
                                  isDense: compact,
                                  border: const OutlineInputBorder(),
                                ),
                                items: _availableGovernorates
                                    .map(
                                      (gov) => DropdownMenuItem(
                                        value: gov,
                                        child: Text(
                                          gov,
                                          overflow: TextOverflow.ellipsis,
                                        ),
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
                              second: DropdownButtonFormField<String>(
                                key: ValueKey(
                                  'area-${_selectedZone?.id}-${_areasForGovernorate.length}',
                                ),
                                isExpanded: true,
                                initialValue: _areasForGovernorate.any(
                                  (zone) => zone.id == _selectedZone?.id,
                                )
                                    ? _selectedZone?.id
                                    : null,
                                decoration: InputDecoration(
                                  labelText: strings.area,
                                  isDense: compact,
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
                                          overflow: TextOverflow.ellipsis,
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
                            ),
                          const SizedBox(height: 12),
                          _ResponsivePair(
                            first: TextFormField(
                              controller: _blockController,
                              decoration: InputDecoration(
                                labelText: strings.block,
                                isDense: compact,
                                border: const OutlineInputBorder(),
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? strings.required
                                      : null,
                            ),
                            second: TextFormField(
                              controller: _streetController,
                              decoration: InputDecoration(
                                labelText: strings.street,
                                isDense: compact,
                                border: const OutlineInputBorder(),
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? strings.required
                                      : null,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _avenueController,
                            decoration: InputDecoration(
                              labelText: strings.avenue,
                              isDense: compact,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _ResponsivePair(
                            first: TextFormField(
                              controller: _houseController,
                              decoration: InputDecoration(
                                labelText: strings.houseNumber,
                                isDense: compact,
                                border: const OutlineInputBorder(),
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? strings.required
                                      : null,
                            ),
                            second: TextFormField(
                              controller: _floorController,
                              decoration: InputDecoration(
                                labelText: strings.floorApartment,
                                isDense: compact,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            strings.isArabic
                                ? 'محفظة الكاش باك'
                                : 'Cashback wallet',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.brandMaroon,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFFDBA74)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        strings.isArabic
                                            ? 'الرصيد ${session.walletBalance.toStringAsFixed(3)} د.ك'
                                            : 'Balance ${session.walletBalance.toStringAsFixed(3)} KD',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        session.walletBalance <= 0
                                            ? (strings.isArabic
                                                ? 'لا يوجد رصيد حالياً. يُضاف الكاش باك بعد التوصيل.'
                                                : 'No balance yet. Cashback is credited after delivery.')
                                            : (strings.isArabic
                                                ? 'تطبيق الرصيد على إجمالي الطلب'
                                                : 'Apply wallet to this order'),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF9A3412),
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: _applyWallet && session.walletBalance > 0,
                                  onChanged: session.walletBalance <= 0
                                      ? null
                                      : (value) =>
                                          setState(() => _applyWallet = value),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            strings.paymentMethod,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.brandMaroon,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _paymentMethods.map((method) {
                              final selected =
                                  method.storageValue == _paymentMethod;
                              return ChoiceChip(
                                label: Text(method.labelFor(locale.localeCode)),
                                selected: selected,
                                selectedColor: AppTheme.brandMaroon,
                                labelStyle: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : AppTheme.brandBlack,
                                  fontWeight: FontWeight.w600,
                                ),
                                onSelected: (_) {
                                  setState(
                                    () => _paymentMethod = method.storageValue,
                                  );
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                          _buildTotals(cart, strings),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 12 : 20,
                      8,
                      compact ? 12 : 20,
                      compact ? 12 : 20,
                    ),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.brandMaroon,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: _submitting
                          ? null
                          : () {
                              if (_checkoutStep == 1) {
                                if (cart.isEmpty) return;
                                setState(() => _checkoutStep = 2);
                                return;
                              }
                              _submit(cart, strings);
                            },
                      child: _submitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _checkoutStep == 1
                                    ? (strings.isArabic
                                        ? 'متابعة إلى التوصيل والدفع'
                                        : 'Continue to details')
                                    : strings.sendOrder(
                                        grandTotal.toStringAsFixed(3),
                                      ),
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: compact ? 14 : 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                    ),
                  ),
                  ),
                ],
              ),
            ),
          );
            },
          ),
        ),
      ),
    );
  }
}

class _CartLine extends StatelessWidget {
  const _CartLine({
    required this.name,
    required this.priceLabel,
    required this.quantity,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String name;
  final String priceLabel;
  final int quantity;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 380;
        final qty = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onDecrease,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$quantity'),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onIncrease,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        );
        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              priceLabel,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
          ],
        );
        if (stacked) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [info, qty],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: info),
              qty,
            ],
          ),
        );
      },
    );
  }
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              first,
              const SizedBox(height: 12),
              second,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.number,
    required this.label,
    required this.active,
  });

  final String number;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor:
              active ? AppTheme.brandMaroon : const Color(0xFFD6D3D1),
          child: Text(
            number,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: active ? AppTheme.brandMaroon : const Color(0xFF78716C),
            ),
          ),
        ),
      ],
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
