import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/kuwait_governorates.dart';
import '../../l10n/app_strings.dart';
import '../../models/cart_item.dart';
import '../../models/customer.dart';
import '../../models/customer_checkout_profile.dart';
import '../../models/dining_table.dart';
import '../../models/delivery_address_details.dart';
import '../../models/delivery_zone.dart';
import '../../models/kitchen.dart';
import '../../models/menu_item.dart';
import '../../models/order.dart';
import '../../models/restaurant_settings.dart';
import '../../models/sales_platform_config.dart';
import '../../services/dining_tables_service.dart';
import '../../services/admin_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/customer_checkout_cache_service.dart';
import '../../services/orders_service.dart';
import '../../services/orders_demo_service.dart';
import '../../services/restaurant_settings_service.dart';
import '../../services/pos_print_helper.dart';
import '../../services/pos_print_settings_service.dart';
import '../../services/pos_operations_service.dart';
import '../../services/offline/pos_sync_service.dart';
import '../../services/pos/pos_barcode_listener.dart';
import '../../services/pos/pos_hardware_bridge.dart';
import '../../services/pos/pos_platform_profile.dart';
import '../../theme/app_theme.dart';
import '../../utils/pos_receipt_html.dart';
import '../../utils/whatsapp_phone.dart';
import '../menu/offer_usage_limit_alert.dart';
import 'admin_order_details_dialog.dart';

import 'pos/pos_kitchen_selector.dart';
import 'pos/pos_print_preview_dialog.dart';
import 'pos/pos_delivery_dispatch.dart';
import 'pos/pos_fast_modifiers_dialog.dart';
import 'pos/pos_platform_selector.dart';
import 'pos/pos_compact_toolbar.dart';
import 'pos/pos_theme.dart';
import 'pos/pos_ui_components.dart';

class AdminPosPanel extends StatefulWidget {
  const AdminPosPanel({
    super.key,
    this.onOrderSubmitted,
    this.onOrdersSubmitted,
    this.onOpenMenu,
    this.onLogout,
    this.restaurantId,
    this.deliveryFee,
    this.dineInTable,
    this.onDineInSessionUpdated,
    this.onDineInKitchenSent,
    this.onDineInReleased,
    this.onOpenTables,
    this.onOpenDriverHandoff,
    this.onOpenOnlineOrders,
    this.tableManagementEnabled = false,
    this.shiftLabel,
  });

  final VoidCallback? onOrderSubmitted;
  final VoidCallback? onOrdersSubmitted;
  final VoidCallback? onOpenMenu;
  final VoidCallback? onLogout;
  final String? restaurantId;
  final double? deliveryFee;
  final DiningTable? dineInTable;
  final ValueChanged<DiningTable>? onDineInSessionUpdated;
  final VoidCallback? onDineInKitchenSent;
  final VoidCallback? onDineInReleased;
  final VoidCallback? onOpenTables;
  final VoidCallback? onOpenDriverHandoff;
  final VoidCallback? onOpenOnlineOrders;
  final bool tableManagementEnabled;
  /// Short caption for the merged maroon POS header (cashier / shift).
  final String? shiftLabel;

  @override
  State<AdminPosPanel> createState() => _AdminPosPanelState();
}

class _AdminPosPanelState extends State<AdminPosPanel> {
  static const _allCategory = 'الكل';
  static const _topCategory = 'الأكثر مبيعاً 🔥';
  static const _menuPageSize = 100;

  final _formKey = GlobalKey<FormState>();
  final _searchFocus = FocusNode();
  final _searchController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _blockController = TextEditingController();
  final _streetController = TextEditingController();
  final _avenueController = TextEditingController();
  final _houseController = TextEditingController();
  final _floorController = TextEditingController();
  final _externalOrderIdController = TextEditingController();
  final _platformDeliveryFeeController = TextEditingController();

  final List<CartItem> _cart = [];
  List<MenuItem> _allItems = const [];
  List<SalesPlatformConfig> _salesPlatforms = SalesPlatformConfig.defaults();
  PosPlatformSelection _platformSelection = PosPlatformSelection(
    platform: SalesPlatformConfig.defaults().first,
  );
  Timer? _lookupDebounce;
  Timer? _sessionSaveTimer;
  Timer? _localCartTimer;
  final _cartTick = ValueNotifier<int>(0);
  var _dineInHydrated = false;
  String? _lastLookupPhone;
  var _lookupInProgress = false;
  var _submitting = false;
  var _isPickup = true;
  /// Foodics order-type chip: local | takeaway | delivery | platforms
  var _orderMode = 'takeaway';
  String _selectedCategory = _allCategory;
  String _paymentMethod = 'كاش';
  String? _selectedGovernorate;
  DeliveryZone? _selectedZone;
  List<DeliveryZone> _zones = const [];
  List<Kitchen> _kitchens = const [];
  var _kitchenManagementEnabled = false;
  var _fleetDeliveryEnabled = false;
  String? _selectedTargetKitchenId;
  String? _autoSuggestedKitchenId;
  List<int> _topItemIds = const [];
  List<Order> _recentOrders = const [];
  int _customerOrderCount = 0;
  var _menuLoading = true;
  String? _menuError;
  PosBarcodeListener? _barcodeListener;

  String get _restaurantId =>
      widget.restaurantId ??
      AdminAuthService.instance.restaurantId ??
      ApiService.defaultRestaurantId;

  String get _restaurantName =>
      AdminAuthService.instance.restaurantName ?? 'المطعم';

  bool get _isDineIn => widget.dineInTable != null;

  bool get _dineInLocked => widget.dineInTable?.isAwaitingCheck ?? false;

  double get _subtotal => _cart.fold(0.0, (sum, item) => sum + item.totalPrice);

  double get _deliveryFee {
    if (_isDineIn) return 0;
    if (_platformSelection.isExternal) {
      final fee = _platformSelection.deliveryFee;
      return fee > 0 ? fee : 0;
    }
    if (_isPickup) return 0;
    return _selectedZone?.deliveryFee ?? 0;
  }

  double get _grandTotal =>
      _subtotal +
      _deliveryFee +
      (_dineInLocked ? (widget.dineInTable?.requestedTip ?? 0) : 0);


  @override
  void initState() {
    super.initState();
    RestaurantSettingsService.instance.addListener(_onSettingsChanged);
    unawaited(posHardwareBridge.initialize());
    assert(() {
      debugPrint(
        'POS runtime storage=${PosPlatformProfile.storageBackendLabel} '
        'web=${PosPlatformProfile.isWeb}',
      );
      return true;
    }());
    _barcodeListener = PosBarcodeListener(
      resolveCatalog: () => _allItems,
      onItemMatched: (item) => unawaited(_handleMenuItemTap(item)),
      isEditingText: posIsEditingText,
      isRouteCurrent: () {
        if (!mounted) return false;
        final route = ModalRoute.of(context);
        return route == null || route.isCurrent;
      },
    )..attach();
    unawaited(_loadPage());
    _phoneController.addListener(_onPhoneChanged);
    unawaited(PosPrintSettingsService.instance.initialize());
  }

  @override
  void dispose() {
    _barcodeListener?.detach();
    _barcodeListener = null;
    RestaurantSettingsService.instance.removeListener(_onSettingsChanged);
    _lookupDebounce?.cancel();
    _sessionSaveTimer?.cancel();
    _localCartTimer?.cancel();
    _cartTick.dispose();
    _phoneController.removeListener(_onPhoneChanged);
    _searchFocus.dispose();
    _searchController.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    _blockController.dispose();
    _streetController.dispose();
    _avenueController.dispose();
    _houseController.dispose();
    _floorController.dispose();
    _externalOrderIdController.dispose();
    _platformDeliveryFeeController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    final settings = RestaurantSettingsService.instance.cached;
    final cachedId = RestaurantSettingsService.instance.cachedRestaurantId;
    if (settings == null || !mounted) return;
    if (cachedId != null &&
        cachedId.isNotEmpty &&
        cachedId != _restaurantId) {
      return;
    }
    setState(() => _applySettings(settings));
  }

  Future<void> _loadPage() async {
    if (mounted) {
      setState(() {
        _menuLoading = true;
        _menuError = null;
      });
    }

    try {
      final cachedSettings = RestaurantSettingsService.instance.cached;
      final cachedId = RestaurantSettingsService.instance.cachedRestaurantId;
      if (cachedSettings != null &&
          (cachedId == null ||
              cachedId.isEmpty ||
              cachedId == _restaurantId)) {
        _applySettings(cachedSettings);
      }

      final first = await ApiService.instance.fetchItemsPage(
        restaurantId: _restaurantId,
        lite: true,
        limit: _menuPageSize,
      );
      _allItems = first.items.where((item) => item.isAvailable).toList();
      unawaited(
        PosSyncService.instance.cacheCatalog(_restaurantId, first.items),
      );
      await _hydrateCartIfNeeded();
      if (!mounted) return;
      setState(() {
        _menuLoading = false;
        _menuError = null;
      });

      unawaited(_loadRemainingMenu(first.total, first.items.length));
      unawaited(_loadPosExtras());
    } catch (error) {
      final cached = await PosSyncService.instance.loadCachedCatalog(
        _restaurantId,
      );
      if (cached.isNotEmpty) {
        _allItems = cached.where((item) => item.isAvailable).toList();
        await _hydrateCartIfNeeded();
        if (!mounted) return;
        setState(() {
          _menuLoading = false;
          _menuError = null;
        });
        unawaited(_loadPosExtras());
        return;
      }
      if (!mounted) return;
      setState(() {
        _menuLoading = false;
        _menuError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<MenuItem> _mergeItems(List<MenuItem> current, List<MenuItem> incoming) {
    final byId = <int, MenuItem>{for (final item in current) item.id: item};
    for (final item in incoming) {
      if (!item.isAvailable) continue;
      byId[item.id] = item;
    }
    return byId.values.toList();
  }

  void _applySettings(RestaurantSettings settings) {
    _kitchenManagementEnabled = settings.kitchenManagementEnabled;
    _fleetDeliveryEnabled = settings.deliveryManagementEnabled;
    final platforms = settings.resolvedSalesPlatforms;
    _salesPlatforms = platforms;
    if (_platformSelection.platform.id.isEmpty ||
        !platforms.any((p) => p.id == _platformSelection.platform.id)) {
      _platformSelection = PosPlatformSelection(
        platform: platforms.firstWhere(
          (p) => p.isLocal,
          orElse: () => platforms.first,
        ),
      );
    }
  }

  Future<void> _loadRemainingMenu(int total, int startOffset) async {
    var offset = startOffset;
    while (offset < total) {
      final page = await ApiService.instance.fetchItemsPage(
        restaurantId: _restaurantId,
        lite: true,
        limit: _menuPageSize,
        offset: offset,
      );
      if (page.items.isEmpty) break;
      offset += page.items.length;
      if (!mounted) return;
      setState(() {
        _allItems = _mergeItems(_allItems, page.items);
      });
    }
    unawaited(PosSyncService.instance.cacheCatalog(_restaurantId, _allItems));
  }

  Future<void> _loadPosExtras() async {
    // Platforms/settings must not depend on zones/kitchens/top-items succeeding.
    unawaited(_reloadSalesPlatforms());

    List<DeliveryZone> zones = const [];
    List<int> topItemIds = const [];
    List<Kitchen> kitchens = const [];
    try {
      zones = await ApiService.instance.fetchDeliveryZones(
        restaurantId: _restaurantId,
      );
    } catch (_) {}
    try {
      topItemIds = await ApiService.instance.fetchTopMenuItemIds(
        restaurantId: _restaurantId,
      );
    } catch (_) {}
    try {
      kitchens = await ApiService.instance.fetchKitchens(
        restaurantId: _restaurantId,
      );
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _zones = zones;
      _kitchens = kitchens;
      _topItemIds = topItemIds;
      if (_selectedGovernorate == null && zones.isNotEmpty) {
        _selectedGovernorate = zones.first.governorate;
      }
      _syncDefaultArea();
      _applyKitchenSuggestion(_selectedZone);
    });
  }

  Future<void> _reloadSalesPlatforms() async {
    try {
      final settings = await RestaurantSettingsService.instance.load(
        restaurantId: _restaurantId,
      );
      if (!mounted) return;
      setState(() => _applySettings(settings));
    } catch (_) {}
  }

  Future<void> _reload() async {
    await _loadPage();
  }

  Future<void> _hydrateCartIfNeeded() async {
    _hydrateDineInCartIfNeeded();
    if (_cart.isNotEmpty) return;
    try {
      final row = await PosSyncService.instance.loadActiveOrder(
        _localCartId,
        restaurantId: _restaurantId,
      );
      if (row == null) return;
      final raw = row['cartItems'];
      if (raw is! List || raw.isEmpty) return;
      final items = DiningTablesService.cartItemsFromSession(
        raw
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList(),
        catalog: _allItems,
      );
      if (items.isEmpty) return;
      _cart
        ..clear()
        ..addAll(items);
      final name = row['customerName']?.toString() ?? '';
      final phone = row['phone']?.toString() ?? '';
      final payment = row['paymentMethod']?.toString() ?? '';
      if (name.isNotEmpty && _nameController.text.trim().isEmpty) {
        _nameController.text = name;
      }
      if (phone.isNotEmpty && _phoneController.text.trim().isEmpty) {
        _phoneController.text = phone;
      }
      if (payment == 'كاش' || payment == 'K-Net') {
        _paymentMethod = payment;
      }
    } catch (_) {}
  }

  String get _localCartId =>
      _isDineIn ? (widget.dineInTable?.id ?? 'walk-in') : 'walk-in';

  void _hydrateDineInCartIfNeeded() {
    if (!_isDineIn || _dineInHydrated) return;
    _dineInHydrated = true;
    final session = widget.dineInTable?.activeSession;
    if (session == null) return;
    if (session.customerName.isNotEmpty) {
      _nameController.text = session.customerName;
    } else {
      _nameController.text = widget.dineInTable?.displayName ?? '';
    }
    if (session.phone.isNotEmpty) {
      _phoneController.text = session.phone;
    }
    if (session.paymentMethod == 'cash') {
      _paymentMethod = 'كاش';
    } else if (session.paymentMethod == 'knet') {
      _paymentMethod = 'K-Net';
    }
    if (session.cartItems.isEmpty) return;
    _cart
      ..clear()
      ..addAll(
        DiningTablesService.cartItemsFromSession(
          session.cartItems,
          catalog: _allItems,
        ),
      );
  }

  void _scheduleDineInSave() {
    _localCartTimer?.cancel();
    _localCartTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_persistLocalCart());
    });
    if (!_isDineIn) return;
    _sessionSaveTimer?.cancel();
    _sessionSaveTimer = Timer(const Duration(milliseconds: 700), () {
      unawaited(_persistDineInSession());
    });
  }

  void _bumpCart() {
    _cartTick.value++;
    _scheduleDineInSave();
  }

  Future<void> _persistLocalCart() async {
    try {
      if (_cart.isEmpty) {
        await PosSyncService.instance.clearActiveOrder(
          _localCartId,
          restaurantId: _restaurantId,
        );
        return;
      }
      await PosSyncService.instance.saveActiveOrder(
        id: _localCartId,
        restaurantId: _restaurantId,
        tableId: widget.dineInTable?.id,
        cartItems: _cart.map(DiningTablesService.cartItemToSessionMap).toList(),
        customerName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        paymentMethod: _paymentMethod,
      );
    } catch (_) {}
  }

  Future<void> _persistDineInSession() async {
    final table = widget.dineInTable;
    if (table == null) return;
    try {
      final updated = await DiningTablesService.instance.updateSession(
        table.id,
        cartItems: List.from(_cart),
        customerName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
      );
      widget.onDineInSessionUpdated?.call(updated);
    } catch (_) {}
  }

  bool _isStaticPicksCategory(String category) {
    final value = category.trim().toLowerCase();
    return value.contains('ذوقك') || value.contains('picks for you');
  }

  List<String> _categories(List<MenuItem> items, List<int> topItemIds) {
    final categories = <String>[_allCategory];
    if (topItemIds.isNotEmpty) categories.add(_topCategory);
    for (final item in items) {
      final category = item.categoryName.trim();
      if (category.isEmpty || _isStaticPicksCategory(category)) continue;
      if (!categories.contains(category)) categories.add(category);
    }
    return categories;
  }

  List<MenuItem> _filteredMenuItems(
    List<MenuItem> items,
    List<int> topItemIds,
  ) {
    final query = _searchController.text.trim();
    Iterable<MenuItem> result = items;

    if (_selectedCategory == _topCategory) {
      final byId = {for (final item in items) item.id: item};
      result = topItemIds.map((id) => byId[id]).whereType<MenuItem>();
    } else if (_selectedCategory != _allCategory) {
      result = items.where(
        (item) => item.categoryName.trim() == _selectedCategory,
      );
    }

    if (query.isNotEmpty) {
      result = result.where((item) => posMatchesSearch(item, query));
    }

    return result.toList();
  }

  void _onSearchChanged(String value) {
    setState(() {});

    final barcodeMatch = posFindBarcodeMatch(_allItems, value);
    if (barcodeMatch != null) {
      _searchController.clear();
      unawaited(_handleMenuItemTap(barcodeMatch));
    }
  }

  List<String> get _availableGovernorates {
    if (_zones.isEmpty) return kuwaitGovernorates;
    return _zones.map((zone) => zone.governorate).toSet().toList()..sort();
  }

  List<DeliveryZone> get _areasForGovernorate {
    if (_selectedGovernorate == null) return const [];
    return _zones
        .where((zone) => zone.governorate == _selectedGovernorate)
        .toList()
      ..sort((a, b) => a.areaName.compareTo(b.areaName));
  }

  void _syncDefaultArea() {
    if (_zones.isEmpty) {
      _selectedZone = null;
      return;
    }
    final areas = _areasForGovernorate;
    if (areas.isEmpty) {
      _selectedZone = null;
      return;
    }
    final currentIsValid =
        _selectedZone != null &&
        areas.any((zone) => zone.id == _selectedZone!.id);
    if (!currentIsValid) _selectedZone = areas.first;
    _applyKitchenSuggestion(_selectedZone);
  }

  Kitchen? _defaultKitchen() {
    if (_kitchens.isEmpty) return null;
    return _kitchens.firstWhere(
      (kitchen) => kitchen.isDefault,
      orElse: () => _kitchens.first,
    );
  }

  void _applyKitchenSuggestion(DeliveryZone? zone) {
    final suggested = zone?.defaultKitchenId?.trim();
    if (suggested != null &&
        suggested.isNotEmpty &&
        _kitchens.any((kitchen) => kitchen.id == suggested)) {
      _autoSuggestedKitchenId = suggested;
      _selectedTargetKitchenId = suggested;
      return;
    }
    final fallback = _defaultKitchen();
    _autoSuggestedKitchenId = fallback?.id;
    _selectedTargetKitchenId = fallback?.id;
  }

  String? get _selectedTargetKitchenName {
    final id = _selectedTargetKitchenId;
    if (id == null) return null;
    for (final kitchen in _kitchens) {
      if (kitchen.id == id) return kitchen.displayName;
    }
    return null;
  }

  DeliveryAddressDetails get _addressDetails => DeliveryAddressDetails(
    block: _blockController.text.trim(),
    street: _streetController.text.trim(),
    avenue: _avenueController.text.trim(),
    houseNumber: _houseController.text.trim(),
    floorApartment: _floorController.text.trim(),
  );

  String _formattedAddress() {
    return _addressDetails.formatArabic(
      governorate: _selectedZone?.governorate ?? _selectedGovernorate ?? '',
      areaName: _selectedZone?.areaName ?? '',
    );
  }

  void _onPhoneChanged() {
    final digits = WhatsAppPhone.digitsOnly(_phoneController.text);
    if (digits.length < 8) {
      _lookupDebounce?.cancel();
      setState(() {
        _recentOrders = const [];
        _customerOrderCount = 0;
      });
      return;
    }
    if (digits == _lastLookupPhone) return;
    _lookupDebounce?.cancel();
    _lookupDebounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(_lookupCustomer(digits));
    });
  }

  Future<void> _lookupCustomer(String normalizedPhone) async {
    if (_lookupInProgress && _lastLookupPhone == normalizedPhone) return;
    setState(() {
      _lookupInProgress = true;
      _lastLookupPhone = normalizedPhone;
    });

    try {
      var profile = await CustomerCheckoutCacheService.instance.loadProfile(
        _restaurantId,
        normalizedPhone,
      );
      profile ??= await ApiService.instance.fetchCustomerCheckoutProfile(
        phone: normalizedPhone,
        restaurantId: _restaurantId,
      );

      if (profile != null && profile.hasUsableData) {
        await CustomerCheckoutCacheService.instance.saveProfile(
          _restaurantId,
          profile,
        );
        _applyProfile(profile);
      }

      if (profile?.customerId != null && profile!.customerId!.isNotEmpty) {
        final detail = await ApiService.instance.fetchCustomerDetail(
          profile.customerId!,
          restaurantId: _restaurantId,
        );
        if (!mounted) return;
        setState(() {
          _recentOrders = _parseOrders(detail).take(5).toList();
          _customerOrderCount = detail.customer.totalOrders;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _recentOrders = const [];
          _customerOrderCount = 0;
        });
      }
    } finally {
      if (mounted) setState(() => _lookupInProgress = false);
    }
  }

  List<Order> _parseOrders(CustomerDetailData detail) {
    return detail.rawOrders
        .map((raw) => Order.fromMap(raw['id']?.toString() ?? '', raw))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void _applyProfile(CustomerCheckoutProfile profile) {
    if (profile.customerName.trim().isNotEmpty) {
      _nameController.text = profile.customerName.trim();
    }
    _blockController.text = profile.addressDetails.block;
    _streetController.text = profile.addressDetails.street;
    _avenueController.text = profile.addressDetails.avenue;
    _houseController.text = profile.addressDetails.houseNumber;
    _floorController.text = profile.addressDetails.floorApartment;

    if (profile.governorate.trim().isNotEmpty) {
      _selectedGovernorate = profile.governorate.trim();
    }

    DeliveryZone? matchedZone;
    final zoneId = profile.deliveryZoneId?.trim();
    if (zoneId != null && zoneId.isNotEmpty) {
      for (final zone in _zones) {
        if (zone.id == zoneId) {
          matchedZone = zone;
          break;
        }
      }
    }

    if (matchedZone == null && profile.areaName.trim().isNotEmpty) {
      for (final zone in _zones) {
        final sameArea = zone.areaName.trim() == profile.areaName.trim();
        final sameGov =
            profile.governorate.isEmpty ||
            zone.governorate.trim() == profile.governorate.trim();
        if (sameArea && sameGov) {
          matchedZone = zone;
          break;
        }
      }
    }

    if (matchedZone != null) {
      _selectedGovernorate = matchedZone.governorate;
      _selectedZone = matchedZone;
      _isPickup = false;
    } else {
      _syncDefaultArea();
    }

    if (profile.paymentMethod.trim().isNotEmpty) {
      _paymentMethod = profile.paymentMethod.trim();
    }

    setState(() {});
  }

  Future<void> _handleMenuItemTap(MenuItem item) async {
    if (_dineInLocked) {
      _showMessage(
        AppStrings.read(context).tr(
          'تم طلب الحساب ولا يمكن إضافة أصناف جديدة',
          'The bill was requested; new items cannot be added',
        ),
      );
      return;
    }
    if (item.hasCustomizations) {
      final cartItem = await showPosFastModifiersDialog(context, item);
      if (cartItem != null && mounted) {
        _cart.add(cartItem);
        _bumpCart();
      }
      return;
    }
    _addToCart(item);
  }

  void _addToCart(MenuItem item) {
    final index = _cart.indexWhere(
      (entry) => entry.menuItem.id == item.id && entry.selectedOptions.isEmpty,
    );
    if (index >= 0) {
      final existing = _cart[index];
      _cart[index] = existing.copyWith(quantity: existing.quantity + 1);
    } else {
      _cart.add(
        CartItem(
          id: '${item.id}_${DateTime.now().microsecondsSinceEpoch}',
          menuItem: item,
          selectedOptions: const [],
          quantity: 1,
        ),
      );
    }
    _bumpCart();
  }

  void _updateCartQuantity(String cartItemId, int quantity) {
    if (_dineInLocked) {
      _showMessage(
        AppStrings.read(context).tr(
          'تم طلب الحساب ولا يمكن تعديل الأصناف',
          'The bill was requested; items cannot be changed',
        ),
      );
      return;
    }
    if (quantity <= 0) {
      _cart.removeWhere((item) => item.id == cartItemId);
    } else {
      final index = _cart.indexWhere((item) => item.id == cartItemId);
      if (index == -1) return;
      _cart[index] = _cart[index].copyWith(quantity: quantity);
    }
    _bumpCart();
  }

  void _clearCart() {
    _cart.clear();
    _sessionSaveTimer?.cancel();
    _localCartTimer?.cancel();
    unawaited(
      PosSyncService.instance.clearActiveOrder(
        _localCartId,
        restaurantId: _restaurantId,
      ),
    );
    _platformDeliveryFeeController.clear();
    if (_platformSelection.isExternal && _platformSelection.deliveryFee != 0) {
      _platformSelection = PosPlatformSelection(
        platform: _platformSelection.platform,
        externalOrderId: _platformSelection.externalOrderId,
        trackCommission: _platformSelection.trackCommission,
        commissionPercent: _platformSelection.commissionPercent,
        manualNetRevenue: _platformSelection.manualNetRevenue,
      );
    }
    _cartTick.value++;
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {});
  }

  void _focusSearch() {
    unawaited(_openSearchOverlay(barcodeMode: false));
  }

  Future<void> _openSearchOverlay({required bool barcodeMode}) async {
    final s = AppStrings.read(context);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black45,
      transitionDuration: Duration.zero,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Dialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          barcodeMode
                              ? Icons.qr_code_scanner_rounded
                              : Icons.search_rounded,
                          color: PosTheme.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            barcodeMode
                                ? s.tr('مسح الباركود', 'Scan barcode')
                                : s.tr('بحث سريع', 'Quick search'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      autofocus: true,
                      onChanged: (value) {
                        _onSearchChanged(value);
                        setDialogState(() {});
                      },
                      decoration: InputDecoration(
                        hintText: barcodeMode
                            ? s.tr(
                                'مرّر الباركود أو اكتبه ثم Enter',
                                'Scan or type barcode then Enter',
                              )
                            : s.tr(
                                'اسم الصنف أو الباركود…',
                                'Item name or barcode…',
                              ),
                        filled: true,
                        fillColor: PosTheme.surfaceAlt,
                        prefixIcon: Icon(
                          barcodeMode
                              ? Icons.qr_code_scanner_rounded
                              : Icons.search_rounded,
                        ),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _clearSearch();
                                  setDialogState(() {});
                                },
                                icon: const Icon(Icons.clear_rounded),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => Navigator.pop(dialogContext),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: () {
                          _clearSearch();
                          Navigator.pop(dialogContext);
                        },
                        child: Text(s.tr('إغلاق', 'Close')),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  bool _validateOrder() {
    final s = AppStrings.read(context);
    if (_cart.isEmpty) {
      _showMessage(
        s.tr('أضف أصنافاً إلى الطلب أولاً', 'Add items to the order first'),
      );
      return false;
    }
    if (_isDineIn) return true;
    if (!(_formKey.currentState?.validate() ?? false)) {
      _showMessage(
        s.tr(
          'يرجى إدخال اسم العميل ورقم الهاتف',
          'Enter the customer name and phone number',
        ),
      );
      return false;
    }
    if (!_isPickup && _zones.isNotEmpty && _selectedZone == null) {
      _showMessage(s.tr('يرجى اختيار منطقة التوصيل', 'Select a delivery area'));
      return false;
    }
    if (!_isPickup &&
        _kitchenManagementEnabled &&
        _kitchens.isNotEmpty &&
        (_selectedTargetKitchenId == null ||
            _selectedTargetKitchenId!.trim().isEmpty)) {
      _showMessage(
        s.tr('يرجى اختيار المطبخ المستهدف', 'Select the target kitchen'),
      );
      return false;
    }
    return true;
  }

  Future<Order?> _sendDineInKitchen() async {
    final table = widget.dineInTable;
    if (table == null || !_validateOrder()) return null;
    // The send-kitchen request already persists the current cart. Prevent the
    // debounced session save from racing it with a second network request.
    _sessionSaveTimer?.cancel();
    _submitting = true;
    _cartTick.value++;
    try {
      final result = await DiningTablesService.instance.sendKitchen(
        table.id,
        cartItems: List.from(_cart),
        customerName: _nameController.text.trim().isEmpty
            ? table.displayName
            : _nameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? '00000000'
            : _phoneController.text.trim(),
        paymentMethod: _paymentMethod,
      );
      widget.onDineInSessionUpdated?.call(result.table);
      (widget.onOrderSubmitted ?? widget.onOrdersSubmitted)?.call();
      final autoPrint = PosPrintHelper.settings.autoPrintKitchen;
      if (autoPrint) {
        // Printing can involve QZ/browser discovery. Start it immediately but
        // do not keep the cashier waiting on the order editor.
        unawaited(
          PosPrintHelper.printIfAuto(
            order: result.order,
            kind: PosReceiptKind.kitchen,
          ),
        );
      } else if (mounted) {
        await showPosPrintPreviewDialog(
          context,
          order: result.order,
          restaurantName: _restaurantName,
          kind: PosReceiptKind.kitchen,
        );
      }
      if (mounted) {
        widget.onDineInKitchenSent?.call();
      }
      return result.order;
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
      return null;
    } finally {
      if (mounted) {
        _submitting = false;
        _cartTick.value++;
      }
    }
  }

  Future<Order?> _checkoutDineIn({
    bool autoPrint = true,
    bool forcePrintCustomer = false,
  }) async {
    final table = widget.dineInTable;
    if (table == null || !_validateOrder()) return null;
    _submitting = true;
    _cartTick.value++;
    try {
      final invoiceNumber = DateTime.now().millisecondsSinceEpoch
          .toString()
          .substring(5);
      final customerName = _nameController.text.trim().isEmpty
          ? table.displayName
          : _nameController.text.trim();
      final phone = _phoneController.text.trim().isEmpty
          ? '00000000'
          : _phoneController.text.trim();
      final requestedPayment = table.requestedPaymentMethod;
      final checkoutPaymentMethod = table.isAwaitingCheck
          ? (requestedPayment == 'knet' ? 'K-Net' : 'كاش')
          : _paymentMethod;
      final shift = PosOperationsService.instance.activeShift;
      var order = OrdersDemoService.orderFromCart(
        cartItems: List.from(_cart),
        customerName: customerName,
        phone: phone,
        address: 'طاولة ${table.displayName}',
        paymentMethod: checkoutPaymentMethod,
        invoiceNumber: invoiceNumber,
        orderSource: 'pos-dine-in',
        orderType: OrderType.dineIn,
        createdFromPos: true,
        shiftId: shift?.id,
        cashierId: shift?.cashierId,
        cashierName: shift?.cashierName,
        tableId: table.id,
        initialStatus: OrderStatus.delivered,
      );
      final requestedTip = table.requestedTip;
      if (table.isAwaitingCheck) {
        order = order.copyWith(
          paymentMethod: checkoutPaymentMethod,
          totalPrice: _subtotal + requestedTip,
        );
      }
      // Checkout contains the final cart, so a pending session save would only
      // add latency and can race the server while it releases the table.
      _sessionSaveTimer?.cancel();
      order = await PosSyncService.instance.commitDineInCheckout(
        order: order,
        restaurantId: _restaurantId,
        tableId: table.id,
        cartItems: List.from(_cart),
        paymentMethod: checkoutPaymentMethod,
        customerName: customerName,
        phone: phone,
        invoiceNumber: invoiceNumber,
        tipAmount: table.isAwaitingCheck ? requestedTip : null,
      );
      if (forcePrintCustomer) {
        unawaited(
          PosPrintHelper.printOrder(
            order: order,
            kind: PosReceiptKind.customer,
          ),
        );
      } else if (autoPrint) {
        unawaited(
          PosPrintHelper.printIfAuto(
            order: order,
            kind: PosReceiptKind.customer,
          ),
        );
      }
      if (!mounted) return order;
      _clearCart();
      widget.onDineInReleased?.call();
      // PosDineInPage refreshes orders from onDineInReleased. Keep the fallback
      // for other hosts without triggering the same refresh twice.
      if (widget.onDineInReleased == null) {
        (widget.onOrderSubmitted ?? widget.onOrdersSubmitted)?.call();
      }
      return order;
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
      return null;
    } finally {
      if (mounted) {
        _submitting = false;
        _cartTick.value++;
      }
    }
  }

  Future<Order?> _submitOrder({bool autoPrint = true}) async {
    if (!_validateOrder()) return null;
    if (_isDineIn) return _checkoutDineIn(autoPrint: autoPrint);
    _submitting = true;
    _cartTick.value++;

    try {
      final invoiceNumber = DateTime.now().millisecondsSinceEpoch
          .toString()
          .substring(5);
      final orderSource = _platformSelection.platform.id;
      final platformMeta = _platformSelection.metaForTotal(_grandTotal);
      final shift = PosOperationsService.instance.activeShift;
      final order = await OrdersService.instance.submitOrderFromCart(
        cartItems: List.from(_cart),
        customerName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _isPickup ? 'استلام من المحل' : _formattedAddress(),
        paymentMethod: _paymentMethod,
        invoiceNumber: invoiceNumber,
        restaurantId: _restaurantId,
        deliveryFee: _deliveryFee,
        governorate: _isPickup ? null : _selectedZone?.governorate,
        areaName: _isPickup ? null : _selectedZone?.areaName,
        deliveryZoneId: _isPickup ? null : _selectedZone?.id,
        addressDetails: _isPickup
            ? const DeliveryAddressDetails()
            : _addressDetails,
        orderSource: orderSource,
        orderType: _isPickup ? OrderType.pickup : OrderType.delivery,
        platformMeta: platformMeta,
        targetKitchenId: _isPickup ? null : _selectedTargetKitchenId,
        targetKitchenName: _isPickup ? null : _selectedTargetKitchenName,
        offlineFirst: true,
        shiftId: shift?.id,
        cashierId: shift?.cashierId,
        cashierName: shift?.cashierName,
      );

      await CustomerCheckoutCacheService.instance.saveProfile(
        _restaurantId,
        CustomerCheckoutProfile(
          phone: _phoneController.text.trim(),
          customerName: _nameController.text.trim(),
          governorate: _selectedZone?.governorate ?? _selectedGovernorate ?? '',
          areaName: _selectedZone?.areaName ?? '',
          deliveryZoneId: _selectedZone?.id,
          addressDetails: _isPickup
              ? const DeliveryAddressDetails()
              : _addressDetails,
          paymentMethod: _paymentMethod,
        ),
      );

      _clearCart();
      (widget.onOrderSubmitted ?? widget.onOrdersSubmitted)?.call();
      unawaited(_dispatchDelivery(order));
      if (autoPrint) {
        unawaited(
          PosPrintHelper.printIfAuto(
            order: order,
            kind: PosReceiptKind.kitchen,
          ),
        );
        unawaited(
          PosPrintHelper.printIfAuto(
            order: order,
            kind: PosReceiptKind.customer,
          ),
        );
      }
      return order;
    } on ApiRequestException catch (error) {
      if (error.isOfferUsageLimit) {
        if (mounted) {
          _showMessage(
            'انتهى حد استخدام العرض، سيتم احتساب الطلب بالسعر العادي',
          );
        }
        return null;
      }
      _showMessage(error.message);
      return null;
    } catch (error) {
      final text = error.toString().replaceFirst('Exception: ', '');
      if (text.contains(kOfferUsageLimitMessage)) {
        if (mounted) {
          _showMessage(
            'انتهى حد استخدام العرض، سيتم احتساب الطلب بالسعر العادي',
          );
        }
        return null;
      }
      _showMessage('تعذر حفظ الطلب: $text');
      return null;
    } finally {
      if (mounted) {
        _submitting = false;
        _cartTick.value++;
      }
    }
  }

  Future<void> _openInvoiceDialog(Order order) async {
    if (!mounted) return;
    await showAdminOrderDetailsDialog(
      context,
      order: order,
      platforms: _salesPlatforms,
      showStatusActions:
          AdminAuthService.instance.isSuperAdmin || !order.isHeldByDriver,
      onStatusChanged: (orderId, status) =>
          OrdersService.instance.updateOrderStatus(orderId, status),
    );
  }

  Future<void> _dispatchDelivery(Order order) async {
    if (!_fleetDeliveryEnabled) return;
    if (_isPickup || _isDineIn) return;
    try {
      await ApiService.instance.createDeliveryRequest(
        customerPhone: order.phone,
        regionId: _selectedZone?.id,
        regionName: _selectedZone?.displayName,
        orderId: order.id,
        cashToCollect: _paymentMethod == 'كاش' ? order.totalPrice : 0,
        customerAddress: order.address,
        restaurantId: _restaurantId,
      );
    } catch (_) {}
  }

  Future<void> _completeAndPrint(PosReceiptKind kind) async {
    if (_submitting) return;
    if (_isDineIn) {
      if (kind == PosReceiptKind.kitchen) {
        if (!_validateOrder()) return;
        final s = AppStrings.read(context);
        _showMessage(
          s.tr('تم إرسال الطلب للمطبخ', 'Order sent to kitchen'),
        );
        unawaited(_sendDineInKitchen());
        return;
      }
      if (!_validateOrder()) return;
      _submitting = true;
      final cartSnapshot = List<CartItem>.from(_cart);
      final nameSnapshot = _nameController.text;
      final phoneSnapshot = _phoneController.text;
      final paymentSnapshot = _paymentMethod;
      _clearCart();
      _submitting = false;
      _showMessage(
        AppStrings.read(context).tr('تم الدفع بنجاح', 'Payment successful'),
      );
      unawaited(
        _checkoutDineInOptimistic(
          cartSnapshot: cartSnapshot,
          customerName: nameSnapshot,
          phone: phoneSnapshot,
          paymentMethod: paymentSnapshot,
        ),
      );
      return;
    }

    if (!_validateOrder()) return;
    _submitting = true;
    final cartSnapshot = List<CartItem>.from(_cart);
    final snapshot = (
      cart: cartSnapshot,
      customerName: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      paymentMethod: _paymentMethod,
      isPickup: _isPickup,
      orderMode: _orderMode,
      deliveryFee: _deliveryFee,
      zone: _selectedZone,
      governorate: _selectedGovernorate,
      addressDetails: _addressDetails,
      platformSelection: _platformSelection,
      targetKitchenId: _selectedTargetKitchenId,
      targetKitchenName: _selectedTargetKitchenName,
      kind: kind,
    );
    _clearCart();
    _submitting = false;
    _showMessage(
      kind == PosReceiptKind.kitchen
          ? AppStrings.read(context).tr(
              'تم إرسال تذكرة المطبخ',
              'Kitchen ticket sent',
            )
          : AppStrings.read(context).tr('تم الدفع بنجاح', 'Payment successful'),
    );
    unawaited(_finalizeWalkInInBackground(snapshot));
  }

  Future<void> _finalizeWalkInInBackground(
    ({
      List<CartItem> cart,
      String customerName,
      String phone,
      String paymentMethod,
      bool isPickup,
      String orderMode,
      double deliveryFee,
      DeliveryZone? zone,
      String? governorate,
      DeliveryAddressDetails addressDetails,
      PosPlatformSelection platformSelection,
      String? targetKitchenId,
      String? targetKitchenName,
      PosReceiptKind kind,
    }) snapshot,
  ) async {
    try {
      final invoiceNumber = DateTime.now().millisecondsSinceEpoch
          .toString()
          .substring(5);
      final orderSource = snapshot.platformSelection.platform.id;
      final platformMeta =
          snapshot.platformSelection.metaForTotal(
        snapshot.cart.fold<double>(0, (sum, item) => sum + item.totalPrice) +
            snapshot.deliveryFee,
      );
      final shift = PosOperationsService.instance.activeShift;
      final order = await OrdersService.instance.submitOrderFromCart(
        cartItems: snapshot.cart,
        customerName: snapshot.customerName,
        phone: snapshot.phone,
        address:
            snapshot.isPickup ? 'استلام من المحل' : snapshot.addressDetails.formatArabic(
                governorate: snapshot.zone?.governorate ?? snapshot.governorate ?? '',
                areaName: snapshot.zone?.areaName ?? '',
              ),
        paymentMethod: snapshot.paymentMethod,
        invoiceNumber: invoiceNumber,
        restaurantId: _restaurantId,
        deliveryFee: snapshot.deliveryFee,
        governorate: snapshot.isPickup ? null : snapshot.zone?.governorate,
        areaName: snapshot.isPickup ? null : snapshot.zone?.areaName,
        deliveryZoneId: snapshot.isPickup ? null : snapshot.zone?.id,
        addressDetails: snapshot.isPickup
            ? const DeliveryAddressDetails()
            : snapshot.addressDetails,
        orderSource: orderSource,
        orderType: snapshot.isPickup ? OrderType.pickup : OrderType.delivery,
        platformMeta: platformMeta,
        targetKitchenId: snapshot.isPickup ? null : snapshot.targetKitchenId,
        targetKitchenName:
            snapshot.isPickup ? null : snapshot.targetKitchenName,
        offlineFirst: true,
        shiftId: shift?.id,
        cashierId: shift?.cashierId,
        cashierName: shift?.cashierName,
      );

      unawaited(
        CustomerCheckoutCacheService.instance.saveProfile(
          _restaurantId,
          CustomerCheckoutProfile(
            phone: snapshot.phone,
            customerName: snapshot.customerName,
            governorate:
                snapshot.zone?.governorate ?? snapshot.governorate ?? '',
            areaName: snapshot.zone?.areaName ?? '',
            deliveryZoneId: snapshot.zone?.id,
            addressDetails: snapshot.isPickup
                ? const DeliveryAddressDetails()
                : snapshot.addressDetails,
            paymentMethod: snapshot.paymentMethod,
          ),
        ),
      );
      (widget.onOrderSubmitted ?? widget.onOrdersSubmitted)?.call();
      unawaited(_dispatchDelivery(order));
      unawaited(
        PosPrintHelper.printOrder(order: order, kind: snapshot.kind),
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        'تعذر مزامنة الطلب: ${error.toString().replaceFirst('Exception: ', '')}',
      );
      if (_cart.isEmpty) {
        _cart.addAll(snapshot.cart);
        _bumpCart();
      }
    }
  }

  Future<void> _checkoutDineInOptimistic({
    required List<CartItem> cartSnapshot,
    required String customerName,
    required String phone,
    required String paymentMethod,
  }) async {
    final table = widget.dineInTable;
    if (table == null) return;
    try {
      final invoiceNumber = DateTime.now().millisecondsSinceEpoch
          .toString()
          .substring(5);
      final requestedPayment = table.requestedPaymentMethod;
      final checkoutPaymentMethod = table.isAwaitingCheck
          ? (requestedPayment == 'knet' ? 'K-Net' : 'كاش')
          : paymentMethod;
      final shift = PosOperationsService.instance.activeShift;
      final subtotal = cartSnapshot.fold<double>(
        0,
        (sum, item) => sum + item.totalPrice,
      );
      var order = OrdersDemoService.orderFromCart(
        cartItems: cartSnapshot,
        customerName: customerName.trim().isEmpty
            ? table.displayName
            : customerName.trim(),
        phone: phone.trim().isEmpty ? '00000000' : phone.trim(),
        address: 'طاولة ${table.displayName}',
        paymentMethod: checkoutPaymentMethod,
        invoiceNumber: invoiceNumber,
        orderSource: 'pos-dine-in',
        orderType: OrderType.dineIn,
        createdFromPos: true,
        shiftId: shift?.id,
        cashierId: shift?.cashierId,
        cashierName: shift?.cashierName,
        tableId: table.id,
        initialStatus: OrderStatus.delivered,
      );
      final requestedTip = table.requestedTip;
      if (table.isAwaitingCheck) {
        order = order.copyWith(
          paymentMethod: checkoutPaymentMethod,
          totalPrice: subtotal + requestedTip,
        );
      }
      order = await PosSyncService.instance.commitDineInCheckout(
        order: order,
        restaurantId: _restaurantId,
        tableId: table.id,
        cartItems: cartSnapshot,
        paymentMethod: checkoutPaymentMethod,
        customerName: customerName.trim().isEmpty
            ? table.displayName
            : customerName.trim(),
        phone: phone.trim().isEmpty ? '00000000' : phone.trim(),
        invoiceNumber: invoiceNumber,
        tipAmount: table.isAwaitingCheck ? requestedTip : null,
      );
      unawaited(
        PosPrintHelper.printOrder(
          order: order,
          kind: PosReceiptKind.customer,
        ),
      );
      if (!mounted) return;
      widget.onDineInReleased?.call();
      if (widget.onDineInReleased == null) {
        (widget.onOrderSubmitted ?? widget.onOrdersSubmitted)?.call();
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
      if (_cart.isEmpty) {
        _cart.addAll(cartSnapshot);
        _bumpCart();
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.f2): PosSubmitIntent(),
        SingleActivator(LogicalKeyboardKey.enter): PosSubmitIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): PosSubmitIntent(),
        SingleActivator(LogicalKeyboardKey.enter, shift: true):
            PosKitchenIntent(),
        SingleActivator(LogicalKeyboardKey.f3): PosKitchenIntent(),
        SingleActivator(LogicalKeyboardKey.f4): PosFocusSearchIntent(),
        SingleActivator(LogicalKeyboardKey.f8): PosClearCartIntent(),
        SingleActivator(LogicalKeyboardKey.escape): PosClearCartIntent(),
      },
      child: Actions(
        actions: {
          PosSubmitIntent: CallbackAction<PosSubmitIntent>(
            onInvoke: (_) {
              if (posIsEditingText()) return null;
              if (!_submitting && _cart.isNotEmpty) {
                unawaited(_completeAndPrint(PosReceiptKind.customer));
              }
              return null;
            },
          ),
          PosKitchenIntent: CallbackAction<PosKitchenIntent>(
            onInvoke: (_) {
              if (posIsEditingText()) return null;
              if (!_submitting && !_dineInLocked && _cart.isNotEmpty) {
                unawaited(_completeAndPrint(PosReceiptKind.kitchen));
              }
              return null;
            },
          ),
          PosFocusSearchIntent: CallbackAction<PosFocusSearchIntent>(
            onInvoke: (_) {
              _focusSearch();
              return null;
            },
          ),
          PosClearCartIntent: CallbackAction<PosClearCartIntent>(
            onInvoke: (_) {
              if (_searchController.text.trim().isNotEmpty) {
                _clearSearch();
                return null;
              }
              if (_cart.isNotEmpty) _clearCart();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Builder(
            builder: (context) {
              if (_menuLoading) {
                return const Center(
                  child: CircularProgressIndicator(color: AppTheme.brandOrange),
                );
              }
              if (_menuError != null) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${s.tr('تعذر تحميل بيانات POS', 'Could not load POS data')}: $_menuError',
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _reload,
                        child: Text(s.tr('إعادة المحاولة', 'Try again')),
                      ),
                    ],
                  ),
                );
              }

              final categories = _categories(_allItems, _topItemIds);
              final menuItems = _filteredMenuItems(_allItems, _topItemIds);

              return LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= PosTheme.breakpoint;
                  final compact = PosTheme.isCompactPos(constraints.maxWidth);
                  final cartW = PosTheme.cartWidthFor(constraints.maxWidth);
                  final menuSection = _buildMenuSection(
                    categories: categories,
                    menuItems: menuItems,
                    wide: wide,
                    compact: compact,
                    availableWidth: constraints.maxWidth,
                  );
                  final cartSection = ListenableBuilder(
                    listenable: _cartTick,
                    builder: (context, _) =>
                        _buildStickyCart(compact: compact),
                  );

                  if (!wide) {
                    return Column(
                      children: [
                        Expanded(flex: 45, child: cartSection),
                        Expanded(flex: 55, child: menuSection),
                      ],
                    );
                  }

                  // Foodics layout: cart ~32% left, menu ~68% right.
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: cartW, child: cartSection),
                      Expanded(child: menuSection),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMenuSection({
    required List<String> categories,
    required List<MenuItem> menuItems,
    required bool wide,
    bool compact = false,
    double availableWidth = 1200,
  }) {
    final s = AppStrings.of(context);
    final menuPaneWidth = wide
        ? (availableWidth - PosTheme.cartWidthFor(availableWidth)).clamp(
            280.0,
            availableWidth,
          )
        : availableWidth;
    // Foodics density: prefer 4 columns so ~16 items fit without scrolling.
    final crossAxisCount = PosTheme.menuCrossAxisCount(menuPaneWidth);
    final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      mainAxisExtent: PosTheme.menuTileExtent(compact),
    );
    return ColoredBox(
      color: PosTheme.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PosCompactToolbar(
            orderMode: _orderMode,
            onSelectOrderMode: _selectOrderMode,
            onOpenSearch: () => unawaited(_openSearchOverlay(barcodeMode: false)),
            onOpenBarcode: () => unawaited(_openSearchOverlay(barcodeMode: true)),
            onOpenTables: widget.onOpenTables,
            onOpenDriverHandoff: widget.onOpenDriverHandoff,
            onOpenOnlineOrders: widget.onOpenOnlineOrders,
            tableManagementEnabled: widget.tableManagementEnabled,
            showOrderModes: !_isDineIn,
            shiftLabel: widget.shiftLabel,
          ),
          if (_searchController.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
              child: Material(
                color: PosTheme.orangeSoft,
                borderRadius: BorderRadius.circular(10),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.filter_alt_rounded, color: PosTheme.orange),
                  title: Text(
                    s.tr(
                      'تصفية: ${_searchController.text.trim()}',
                      'Filter: ${_searchController.text.trim()}',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  trailing: IconButton(
                    tooltip: s.tr('مسح البحث', 'Clear search'),
                    onPressed: _clearSearch,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ),
            ),
          _buildCategoryChipsBar(categories),
          Expanded(
            child: menuItems.isEmpty
                ? Center(
                    child: Text(
                      s.tr('لا توجد أصناف مطابقة', 'No matching items'),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                    cacheExtent: 360,
                    gridDelegate: gridDelegate,
                    itemCount: menuItems.length,
                    itemBuilder: (context, index) {
                      final item = menuItems[index];
                      return RepaintBoundary(
                        child: PosMenuItemCard(
                          key: ValueKey(item.id),
                          item: item,
                          compact: true,
                          onTap: () => unawaited(_handleMenuItemTap(item)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _selectOrderMode(String mode) {
    final local = _salesPlatforms.firstWhere(
      (p) => p.isLocal,
      orElse: () => _salesPlatforms.first,
    );
    final externals =
        _salesPlatforms.where((p) => p.isExternal).toList(growable: false);

    setState(() {
      _orderMode = mode;
      switch (mode) {
        case 'local':
        case 'takeaway':
          _orderMode = 'takeaway';
          _isPickup = true;
          _platformSelection = PosPlatformSelection(
            platform: local,
            externalOrderId: _platformSelection.externalOrderId,
          );
          _platformDeliveryFeeController.clear();
          break;
        case 'delivery':
          _isPickup = false;
          _platformSelection = PosPlatformSelection(
            platform: local,
            externalOrderId: _platformSelection.externalOrderId,
          );
          _platformDeliveryFeeController.clear();
          break;
        case 'platforms':
          final platform = _platformSelection.isExternal
              ? _platformSelection.platform
              : (externals.isNotEmpty ? externals.first : local);
          _isPickup = true;
          _platformSelection = PosPlatformSelection(
            platform: platform,
            externalOrderId: _platformSelection.externalOrderId,
            deliveryFee: _platformSelection.deliveryFee,
            trackCommission: platform.isExternal,
            commissionPercent:
                platform.isExternal ? platform.commissionPercent : null,
          );
          break;
      }
    });

    if (mode == 'delivery') {
      unawaited(_openDeliveryAddressDialog());
    }
  }

  Widget _buildCategoryChipsBar(List<String> categories) {
    return Container(
      color: PosTheme.surface,
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: categories.length,
          separatorBuilder: (_, _) => const SizedBox(width: 5),
          itemBuilder: (context, index) {
            final category = categories[index];
            final selected = _selectedCategory == category;
            return FilterChip(
              visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              label: Text(
                category,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: selected ? Colors.white : PosTheme.textPrimary,
                ),
              ),
              selected: selected,
              showCheckmark: false,
              selectedColor: PosTheme.orange,
              backgroundColor: PosTheme.surfaceAlt,
              side: BorderSide(
                color: selected ? PosTheme.orange : PosTheme.border,
              ),
              onSelected: (_) => setState(() => _selectedCategory = category),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStickyCart({bool compact = false}) {
    final s = AppStrings.of(context);
    final pad = compact ? 10.0 : 12.0;
    final commission = _platformSelection.isExternal
        ? _platformSelection.estimatedCommission(_grandTotal)
        : null;
    return ColoredBox(
      color: PosTheme.surface,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_isDineIn)
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
                child: PosPlatformSelector(
                  platforms: _salesPlatforms,
                  selection: _platformSelection,
                  orderTotal: _grandTotal,
                  externalOrderIdController: _externalOrderIdController,
                  deliveryFeeController: _platformDeliveryFeeController,
                  showSourceToggle: false,
                  compactHeader: true,
                  onChanged: (next) {
                    setState(() {
                      _platformSelection = next;
                      if (next.isExternal) {
                        _orderMode = 'platforms';
                      }
                    });
                  },
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
              child: _buildCustomerFields(),
            ),
            if (!_isDineIn && !_isPickup && _orderMode == 'delivery')
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
                child: _buildDeliverySummary(),
              ),
            if (_isDineIn)
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
                child: Text(
                  '${s.tr('طلب صالة', 'Dine-in order')} — ${widget.dineInTable!.displayName}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, 10, pad, 6),
                child: _buildCartBody(compact: compact),
              ),
            ),
            if (commission != null && commission > 0)
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: PosTheme.orangeSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'عمولة المنصة: ${commission.toStringAsFixed(3)} د.ك',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: PosTheme.orange,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
            _buildCheckoutFooter(compact: compact),
          ],
        ),
      ),
    );
  }

  Widget _buildCartBody({bool compact = false}) {
    final s = AppStrings.of(context);
    if (_cart.isEmpty) {
      return Container(
        decoration: PosTheme.card(color: PosTheme.surfaceAlt),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(compact ? 14 : 24),
            child: Text(
              s.tr(
                'السلة فارغة — اختر أصنافاً من المنيو',
                'The cart is empty — select items from the menu',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: PosTheme.textMuted,
                fontSize: compact ? 12.5 : 14,
              ),
            ),
          ),
        ),
      );
    }

    return ListView(
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: _clearCart,
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: Text(s.tr('تفريغ F8', 'Clear F8')),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: PosTheme.textMuted,
              padding: EdgeInsets.zero,
            ),
          ),
        ),
        ..._cart.map(
          (item) => PosCartLine(
            item: item,
            onIncrease: () => _updateCartQuantity(item.id, item.quantity + 1),
            onDecrease: () => _updateCartQuantity(item.id, item.quantity - 1),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerFields() {
    final s = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: s.tr('الهاتف', 'Phone'),
                  isDense: true,
                  suffixIcon: _lookupInProgress
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : const Icon(Icons.person_search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                validator: (value) {
                  if (_isDineIn) return null;
                  return (value == null || value.trim().length < 8)
                      ? s.required
                      : null;
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: s.customerName,
                  isDense: true,
                  prefixIcon: const Icon(Icons.person_outline, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                validator: (value) {
                  if (_isDineIn) return null;
                  return (value == null || value.trim().isEmpty)
                      ? s.required
                      : null;
                },
              ),
            ),
          ],
        ),
        if (_customerOrderCount > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: PosTheme.card(color: PosTheme.accentSoft),
            child: Text(
              s.tr(
                'عميل مسجّل — $_customerOrderCount طلب سابق',
                'Returning customer — $_customerOrderCount previous orders',
              ),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDeliverySummary() {
    final s = AppStrings.of(context);
    final zone = _selectedZone;
    final summary = zone == null
        ? s.tr(
            'اضغط لإدخال المحافظة والمنطقة والعنوان',
            'Tap to enter governorate, area, and address',
          )
        : '${zone.areaName} (${zone.deliveryFee.toStringAsFixed(3)} ${s.currency})';
    return Material(
      color: const Color(0xFFE0F2FE),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => unawaited(_openDeliveryAddressDialog()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.location_on_outlined, color: Color(0xFF0369A1)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (zone != null && _formattedAddress().trim().isNotEmpty)
                      Text(
                        _formattedAddress(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF475569),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(
                Icons.edit_outlined,
                size: 18,
                color: Color(0xFF0369A1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDeliveryAddressDialog() async {
    final s = AppStrings.read(context);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 24,
              ),
              child: SizedBox(
                width: 520,
                height: MediaQuery.sizeOf(dialogContext).height * 0.78,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.tr('بيانات التوصيل', 'Delivery details'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: _buildDeliveryFields(
                          onDialogUpdate: () => setDialogState(() {}),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: Text(s.tr('حفظ العنوان', 'Save address')),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (mounted) setState(() {});
  }

  Widget _buildDeliveryFields({VoidCallback? onDialogUpdate}) {
    final s = AppStrings.of(context);
    void refresh(VoidCallback apply) {
      apply();
      setState(() {});
      onDialogUpdate?.call();
    }

    return Column(
      children: [
        DropdownButtonFormField<String>(
          value: _availableGovernorates.contains(_selectedGovernorate)
              ? _selectedGovernorate
              : (_availableGovernorates.isNotEmpty
                    ? _availableGovernorates.first
                    : null),
          decoration: InputDecoration(
            labelText: s.governorate,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          items: _availableGovernorates
              .map((gov) => DropdownMenuItem(value: gov, child: Text(gov)))
              .toList(),
          onChanged: (value) {
            refresh(() {
              _selectedGovernorate = value;
              _syncDefaultArea();
            });
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<DeliveryZone>(
          value: _selectedZone,
          decoration: InputDecoration(
            labelText: s.area,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          items: _areasForGovernorate
              .map(
                (zone) => DropdownMenuItem(
                  value: zone,
                  child: Text(
                    '${zone.areaName} (${zone.deliveryFee.toStringAsFixed(3)} د.ك)',
                  ),
                ),
              )
              .toList(),
          onChanged: (value) => refresh(() {
            _selectedZone = value;
            _applyKitchenSuggestion(value);
          }),
        ),
        if (!_isPickup &&
            _kitchenManagementEnabled &&
            _kitchens.isNotEmpty) ...[
          const SizedBox(height: 8),
          PosKitchenSelector(
            kitchens: _kitchens,
            selectedId: _selectedTargetKitchenId,
            autoSuggestedId: _autoSuggestedKitchenId,
            onChanged: (id) => refresh(() => _selectedTargetKitchenId = id),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _blockController,
                decoration: InputDecoration(
                  labelText: s.tr('القطعة', 'Block'),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: _streetController,
                decoration: InputDecoration(
                  labelText: s.tr('الشارع', 'Street'),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _avenueController,
                decoration: InputDecoration(
                  labelText: s.tr('الجادة', 'Avenue'),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: _houseController,
                decoration: InputDecoration(
                  labelText: s.tr('البيت', 'House'),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentSelector() {
    final s = AppStrings.of(context);
    return Row(
      children: [
        Expanded(
          child: _PaymentModeButton(
            label: s.cash,
            icon: Icons.payments_outlined,
            color: const Color(0xFF059669),
            selected: _paymentMethod == 'كاش',
            onTap: () => setState(() => _paymentMethod = 'كاش'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _PaymentModeButton(
            label: 'K-Net',
            icon: Icons.credit_card,
            color: const Color(0xFF2563EB),
            selected: _paymentMethod == 'K-Net',
            onTap: () => setState(() => _paymentMethod = 'K-Net'),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckoutFooter({bool compact = false}) {
    final s = AppStrings.of(context);
    final btnH = compact ? 56.0 : 62.0;
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 12,
        compact ? 8 : 10,
        compact ? 10 : 12,
        compact ? 10 : 12,
      ),
      decoration: const BoxDecoration(
        color: PosTheme.surfaceAlt,
        border: Border(top: BorderSide(color: PosTheme.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.tr('المجموع الفرعي', 'Subtotal'),
                  style: const TextStyle(
                    color: PosTheme.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
              Text(
                '${_subtotal.toStringAsFixed(3)} د.ك',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if ((_deliveryFee > 0 || (!_isPickup && !_isDineIn)) && !_isDineIn)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.tr('التوصيل', 'Delivery'),
                      style: const TextStyle(
                        color: PosTheme.textMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  Text(
                    '${_deliveryFee.toStringAsFixed(3)} د.ك',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          if (_dineInLocked && (widget.dineInTable?.requestedTip ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.tr('الإكرامية', 'Tip'),
                      style: const TextStyle(
                        color: PosTheme.textMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  Text(
                    '${widget.dineInTable!.requestedTip.toStringAsFixed(3)} د.ك',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          _buildPaymentSelector(),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  s.tr('الإجمالي', 'Total'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                '${_grandTotal.toStringAsFixed(3)} د.ك',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  color: PosTheme.orange,
                ),
              ),
            ],
          ),
          if (_fleetDeliveryEnabled && !_isPickup && !_isDineIn) ...[
            const SizedBox(height: 8),
            PosExpressDriverButton(
              zones: _zones,
              restaurantId: _restaurantId,
              initialPhone: _phoneController.text,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: PosTheme.orange,
                    foregroundColor: Colors.white,
                    minimumSize: Size.fromHeight(btnH),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _submitting || _dineInLocked
                      ? null
                      : () => _completeAndPrint(PosReceiptKind.kitchen),
                  icon: const Icon(Icons.print_rounded, size: 22),
                  label: Text(
                    s.tr('مطبخ', 'Kitchen'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: PosTheme.green,
                    foregroundColor: Colors.white,
                    minimumSize: Size.fromHeight(btnH),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _submitting
                      ? null
                      : () => _completeAndPrint(PosReceiptKind.customer),
                  icon: const Icon(Icons.receipt_long_rounded, size: 22),
                  label: Text(
                    s.tr('فاتورة', 'Checkout'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentModeButton extends StatelessWidget {
  const _PaymentModeButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color : PosTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : PosTheme.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : color,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: selected ? Colors.white : PosTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
