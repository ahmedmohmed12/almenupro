import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/order.dart';
import '../models/restaurant_settings.dart';
import '../models/staff_user.dart';
import '../utils/admin_deep_link.dart';
import '../utils/admin_route_nav.dart';
import '../utils/admin_settings_url.dart';
import '../utils/firebase_config.dart';
import '../utils/food_cost_utils.dart';
import '../utils/image_url.dart';
import '../utils/whatsapp_phone.dart';
import '../services/admin_auth_service.dart';
import '../services/admin_order_focus_service.dart';
import '../services/admin_order_monitor_service.dart';
import '../services/admin_runtime_keepalive.dart';
import '../services/api_service.dart';
import '../services/incoming_order_auto_accept_service.dart';
import '../services/menu_storage_service.dart';
import '../services/orders_service.dart';
import '../services/order_alert_sound_service.dart';
import '../services/order_browser_notification_service.dart';
import '../services/pos_operations_service.dart';
import '../services/restaurant_settings_service.dart';
import '../services/super_admin_scope_service.dart';
import '../services/talabat_menu_service.dart';
import '../widgets/admin/admin_analytics_reports_panel.dart';
import '../widgets/admin/admin_corner_toast.dart';
import '../widgets/admin/admin_pos_roles_staff_card.dart';
import '../widgets/admin/pos/pos_cashier_login_panel.dart';
import '../widgets/admin/pos/pos_shift_shell.dart';
import '../widgets/admin/kitchen_station_screen.dart';
import '../widgets/admin/admin_delivery_zones_panel.dart';
import '../widgets/admin/admin_offers_panel.dart';
import '../widgets/admin/admin_reviews_panel.dart';
import '../widgets/admin/admin_expenses_panel.dart';
import '../widgets/admin/admin_item_addons_editor.dart';
import '../widgets/admin/admin_item_linked_sides_editor.dart';
import '../widgets/admin/admin_menu_panel.dart';
import '../widgets/admin/admin_orders_panel.dart';
import '../widgets/admin/admin_customers_panel.dart';
import '../widgets/admin/admin_sidebar.dart';
import '../widgets/admin/settings/admin_settings_tab.dart';
import '../widgets/admin/settings/admin_settings_tabbed_panel.dart';
import '../widgets/admin/admin_menu_sidebar_footer.dart';
import '../widgets/admin/admin_super_restaurants_panel.dart';
import '../widgets/admin/admin_tables_panel.dart';
import '../widgets/admin/admin_sound_settings_card.dart';
import '../widgets/admin/admin_top_header.dart';
import '../widgets/admin/admin_smart_upsell_panel.dart';
import '../widgets/admin/admin_working_hours_card.dart';
import '../widgets/app_error_boundary.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with WidgetsBindingObserver {
  final _ordersPanelKey = GlobalKey<AdminOrdersPanelState>();
  final _shellScaffoldKey = GlobalKey<ScaffoldState>();

  bool _isAuthenticated = false;
  bool _isSuperAdmin = false;
  bool _isLoggingIn = false;
  var _loginMode = 0;
  final _usernameController = TextEditingController();
  final _slugController = TextEditingController(text: 'molton-cookies');
  final _cashierNameController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;
  String? _restaurantLabel;
  int _selectedIndex = AdminSidebar.posIndex;
  AdminMenuPanelStatus? _menuPanelStatus;
  var _menuRevision = 0;

  final _whatsappController = TextEditingController();
  String _whatsappCountryCode = WhatsAppPhone.defaultCountryCode;
  bool _isSavingSettings = false;
  RestaurantSettings? _loadedSettings;
  DateTime? _lastRuntimeResumeAt;

  bool get _whatsappConfigured => _loadedSettings?.hasWhatsappNumber ?? false;

  bool get _tableManagementEnabled =>
      _loadedSettings?.tableManagementEnabled == true;

  bool get _kitchenManagementEnabled =>
      _loadedSettings?.kitchenManagementEnabled == true;

  List<AdminSidebarItem> get _sidebarItems {
    if (_isSuperAdmin) {
      return [
        ...AdminSidebar.superAdminItems,
        if (SuperAdminScopeService.instance.hasSelection &&
            _tableManagementEnabled)
          AdminSidebar.tablesItem,
      ];
    }
    return [
      ...AdminSidebar.defaultItems,
      if (_tableManagementEnabled) AdminSidebar.tablesItem,
    ];
  }

  bool get _isCashierSession => AdminAuthService.instance.isCashier;
  bool get _isKitchenSession => AdminAuthService.instance.isKitchen;

  int get _settingsNavIndex => _isSuperAdmin
      ? AdminSidebar.superSettingsIndex
      : AdminSidebar.settingsIndex;

  AdminSettingsTab _activeSettingsTab() {
    if (kIsWeb) return readSettingsTabFromUrl();
    return AdminSettingsTab.whatsapp;
  }

  void _openSettingsTab(AdminSettingsTab tab) {
    setState(() => _selectedIndex = _settingsNavIndex);
    writeSettingsTabToUrl(tab);
  }

  bool get _shouldShowWhatsappBanner {
    if (_isCashierSession || _isKitchenSession) return false;
    if (_isSuperAdmin && !SuperAdminScopeService.instance.hasSelection) {
      return false;
    }
    return !_whatsappConfigured;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    attachAdminRuntimeKeepAlive(_onRuntimeResume);
    _bootstrapAuth();
    OrderAlertSoundService.instance.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onRuntimeResume();
    }
  }

  void _onRuntimeResume() {
    if (!_isAuthenticated) return;
    final now = DateTime.now();
    if (_lastRuntimeResumeAt != null &&
        now.difference(_lastRuntimeResumeAt!) <
            const Duration(milliseconds: 400)) {
      return;
    }
    _lastRuntimeResumeAt = now;
    unawaited(_resumeBackgroundOperations());
  }

  Future<void> _resumeBackgroundOperations() async {
    await OrdersService.instance.resumeRealtime();
    IncomingOrderAutoAcceptService.instance.resumeFromBackground();
    await OrderAlertSoundService.instance.resumeAfterForeground();
    if (AdminOrderMonitorService.instance.isRunning) {
      await AdminOrderMonitorService.instance.resumeRealtime();
    }
  }

  Future<void> _initSuperAdminScope() async {
    if (!AdminAuthService.instance.isSuperAdmin) return;
    await SuperAdminScopeService.instance.initialize();
    await SuperAdminScopeService.instance.refreshRestaurants();
    SuperAdminScopeService.instance.addListener(_onSuperAdminScopeChanged);
    if (mounted) setState(() {});
  }

  void _onSuperAdminScopeChanged() {
    if (!mounted) return;
    RestaurantSettingsService.instance.clearCache();
    setState(() {});
    unawaited(_loadSettings());
  }

  Future<void> _bootstrapAuth() async {
    await AdminAuthService.instance.initialize();
    if (!mounted) return;

    if (AdminAuthService.instance.isLoggedIn) {
      setState(() {
        _isAuthenticated = true;
        _isSuperAdmin = AdminAuthService.instance.isSuperAdmin;
        _restaurantLabel = AdminAuthService.instance.restaurantName;
        _selectedIndex = AdminAuthService.instance.isSuperAdmin
            ? AdminSidebar.superRestaurantsIndex
            : AdminSidebar.posIndex;
      });
      _applyAuthenticatedDeepLink();
      await _restoreCashierSessionIfNeeded();
      await _initSuperAdminScope();
      await _loadSettings();
      if (!AdminAuthService.instance.isSuperAdmin &&
          !AdminAuthService.instance.isCashier &&
          !AdminAuthService.instance.isKitchen) {
        await _startAdminMonitoring();
      }
    } else {
      _captureGuestDeepLink();
      await _loadSettings();
    }
  }

  Uri get _locationUri => kIsWeb ? Uri.base : Uri(path: '/admin');

  void _captureGuestDeepLink() {
    final uri = _locationUri;
    final orderRef = AdminDeepLink.parseOrderRef(uri);
    final redirect = AdminDeepLink.parseRedirect(uri) ??
        (orderRef != null ? AdminDeepLink.orderPath(orderRef) : null) ??
        AdminDeepLink.sanitizeRedirect(readStoredAdminRedirect());
    if (redirect == null) return;

    AdminOrderFocusService.instance.rememberRedirect(redirect);
    storeAdminRedirect(redirect);
    final focused = AdminDeepLink.parseOrderRef(Uri.parse(redirect));
    if (focused != null) {
      AdminOrderFocusService.instance.requestOrder(focused);
    }
    replaceAdminPath(AdminDeepLink.loginWithRedirect(redirect));
  }

  void _applyAuthenticatedDeepLink() {
    final uri = _locationUri;
    final redirect = AdminDeepLink.parseRedirect(uri) ??
        AdminOrderFocusService.instance.consumeRedirect() ??
        AdminDeepLink.sanitizeRedirect(readStoredAdminRedirect());
    clearStoredAdminRedirect();

    final orderRef = AdminDeepLink.parseOrderRef(uri) ??
        (redirect == null
            ? null
            : AdminDeepLink.parseOrderRef(Uri.parse(redirect)));
    if (orderRef == null) return;

    replaceAdminPath(AdminDeepLink.orderPath(orderRef));
    AdminOrderFocusService.instance.requestOrder(orderRef);
    unawaited(OrdersService.instance.refreshOrders());
    if (_isCashierSession || _isKitchenSession || _isSuperAdmin) {
      if (mounted) setState(() {});
      return;
    }
    _selectedIndex = AdminSidebar.ordersIndex;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    detachAdminRuntimeKeepAlive();
    WidgetsBinding.instance.removeObserver(this);
    SuperAdminScopeService.instance.removeListener(_onSuperAdminScopeChanged);
    AdminOrderMonitorService.instance.stop();
    _usernameController.dispose();
    _slugController.dispose();
    _cashierNameController.dispose();
    _passwordController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final restaurantId = SuperAdminScopeService.instance.effectiveRestaurantId;
      final settings = await RestaurantSettingsService.instance.load(
  restaurantId: restaurantId,
);
      _loadedSettings = settings;
      _whatsappCountryCode = settings.whatsappCountryCode;
      _whatsappController.text = settings.whatsappPhone;
      if (!settings.tableManagementEnabled &&
          (_selectedIndex == AdminSidebar.tablesIndex ||
              _selectedIndex == AdminSidebar.superTablesIndex)) {
        _selectedIndex = _isSuperAdmin
            ? AdminSidebar.superPosIndex
            : AdminSidebar.posIndex;
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
      _loadedSettings = null;
      _whatsappCountryCode = WhatsAppPhone.defaultCountryCode;
      _whatsappController.clear();
      if (mounted) setState(() {});
    }
  }

  Future<void> _saveWhatsappNumber() async {
    if (_whatsappController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال رقم الواتساب')),
      );
      return;
    }
    setState(() => _isSavingSettings = true);

    try {
      final restaurantId = SuperAdminScopeService.instance.effectiveRestaurantId;
      await RestaurantSettingsService.instance.saveWhatsappNumber(
        restaurantId: restaurantId,
        countryCode: _whatsappCountryCode,
        phone: _whatsappController.text.trim(),
      );
      if (!mounted) return;
      final display = WhatsAppPhone.formatDisplay(
        _whatsappCountryCode,
        _whatsappController.text.trim(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFirebaseConfigured
                ? 'تم حفظ رقم الواتساب ($display) بنجاح!'
                : 'تم حفظ الرقم ($display) على السيرفر.',
          ),
        ),
      );
      await _loadSettings();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ رقم الواتساب: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSavingSettings = false);
    }
  }

  Future<void> _login() async {
    setState(() {
      _isLoggingIn = true;
      _errorMessage = null;
    });

    try {
      if (_loginMode == 1) {
        await AdminAuthService.instance.loginSuperAdmin(
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        );
      } else if (_loginMode == 2) {
        final result = await AdminAuthService.instance.loginCashier(
          restaurantName: _slugController.text.trim(),
          cashierName: _cashierNameController.text.trim(),
          password: _passwordController.text,
        );
        if (!result.session.isKitchen) {
          PosOperationsService.instance.applyCashierSession(result.cashierSession);
        }
      } else {
        await AdminAuthService.instance.loginRestaurantAdmin(
          restaurantSlug: _slugController.text.trim(),
          password: _passwordController.text,
        );
      }

      if (!mounted) return;
      setState(() {
        _isAuthenticated = true;
        _isSuperAdmin = AdminAuthService.instance.isSuperAdmin;
        _restaurantLabel = AdminAuthService.instance.restaurantName;
        _selectedIndex = _isSuperAdmin
            ? AdminSidebar.superRestaurantsIndex
            : AdminSidebar.posIndex;
      });
      _applyAuthenticatedDeepLink();

      OrderAlertSoundService.instance.unlockFromUserGesture();
      await _initSuperAdminScope();
      await _loadSettings();
      if (!AdminAuthService.instance.isSuperAdmin &&
          !AdminAuthService.instance.isCashier &&
          !AdminAuthService.instance.isKitchen) {
        await _startAdminMonitoring();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('تسجيل الخروج'),
          content: const Text('هل تريد تسجيل الخروج من لوحة التحكم؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6B1124),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تسجيل الخروج'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await _logout();
    }
  }

  Future<void> _logout() async {
    AdminOrderMonitorService.instance.stop();
    SuperAdminScopeService.instance.removeListener(_onSuperAdminScopeChanged);
    await SuperAdminScopeService.instance.clearSelection();
    PosOperationsService.instance.clearCashierSession();
    await AdminAuthService.instance.logout();
    AdminOrderFocusService.instance.clear();
    clearStoredAdminRedirect();
    replaceAdminPath('/admin');
    if (!mounted) return;
    setState(() {
      _isAuthenticated = false;
      _isSuperAdmin = false;
      _restaurantLabel = null;
      _passwordController.clear();
      _cashierNameController.clear();
      _selectedIndex = AdminSidebar.posIndex;
    });
  }

  Future<void> _restoreCashierSessionIfNeeded() async {
    final session = AdminAuthService.instance.session;
    if (session == null || !session.isCashier) return;
    final stored = await AdminAuthService.instance.loadCashierPermissions();
    PosOperationsService.instance.applyCashierSession(
      PosCashierSession(
        staff: StaffUser(
          id: session.staffId ?? 'cashier',
          name: session.staffName ?? 'كاشير',
          roleId: stored?.roleId.isNotEmpty == true ? stored!.roleId : 'cashier',
        ),
        permissions: stored?.permissions ?? const {},
        roleId: stored?.roleId ?? 'cashier',
      ),
    );
  }

  Future<void> _startAdminMonitoring() async {
    if (_isSuperAdmin ||
        AdminAuthService.instance.isSuperAdmin ||
        AdminAuthService.instance.isCashier ||
        AdminAuthService.instance.isKitchen) {
      return;
    }

    final monitor = AdminOrderMonitorService.instance;
    monitor.onNewPendingOrder = _onNewPendingOrderDetected;
    await monitor.start();
    if (!mounted) return;
    await _maybeRequestBrowserNotifications();
  }

  void _onNewPendingOrderDetected(Order order) {
    if (!mounted || _isSuperAdmin) return;
    AdminCornerToast.show(
      context,
      '🔔 طلب جديد #${order.invoiceNumber ?? order.id.substring(0, 6)}',
      duration: const Duration(seconds: 3),
      maxWidth: 180,
    );
  }

  Future<void> _maybeRequestBrowserNotifications() async {
    final notificationService = OrderBrowserNotificationService.instance;
    if (!notificationService.isSupported) return;

    final prefs = await SharedPreferences.getInstance();
    const promptKey = 'browser_notifications_prompted';
    final alreadyPrompted = prefs.getBool(promptKey) ?? false;
    final status = await notificationService.permissionStatus();

    if (status == 'granted') return;
    if (alreadyPrompted && status == 'denied') return;

    if (!mounted) return;

    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تفعيل إشعارات الطلبات'),
        content: const Text(
          'اسمح بإشعارات المتصفح لتصلك تنبيهات فورية بالطلبات الجديدة '
          'حتى لو كان تبويب لوحة التحكم في الخلفية.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لاحقاً'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6B1124),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تفعيل الإشعارات', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    await prefs.setBool(promptKey, true);
    if (allow == true) {
      await notificationService.requestPermission();
    }
  }


  Future<void> _showItemDialog({MenuItemRecord? record}) async {
    final isEditing = record != null;
    final Map<String, dynamic>? data = isEditing ? record.data : null;

    final nameController = TextEditingController(
      text: data?['nameAr']?.toString() ??
          data?['name_ar']?.toString() ??
          data?['name']?.toString() ??
          '',
    );
    final nameEnController = TextEditingController(
      text: data?['nameEn']?.toString() ?? data?['name_en']?.toString() ?? '',
    );
    final descController = TextEditingController(
      text: data?['descriptionAr']?.toString() ??
          data?['description_ar']?.toString() ??
          data?['description']?.toString() ??
          '',
    );
    final descEnController = TextEditingController(
      text: data?['descriptionEn']?.toString() ??
          data?['description_en']?.toString() ??
          '',
    );
    final priceController = TextEditingController(
      text: data != null ? data['price'].toString() : '',
    );
    final costPriceRaw = data?['costPrice'] ?? data?['cost_price'];
    final costPriceController = TextEditingController(
      text: costPriceRaw != null && costPriceRaw.toString().isNotEmpty
          ? costPriceRaw.toString()
          : '',
    );
    final originalPriceController = TextEditingController(
      text: (data?['originalPrice'] ?? data?['original_price'] ?? '').toString(),
    );
    final categoryController = TextEditingController(
      text: data?['categoryName'] ?? 'أشهر الأصناف',
    );
    final imageUrlController = TextEditingController(
      text: normalizeMenuImageUrl(data?['imageUrl'] as String?),
    );
    var isAvailable = data?['isAvailable'] as bool? ?? true;
    var addonOptions = (data?['options'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
    var linkedItemIds = (data?['linkedItemIds'] as List<dynamic>? ??
            data?['linked_item_ids'] as List<dynamic>? ??
            [])
        .map((id) => int.tryParse(id.toString()))
        .whereType<int>()
        .toList();
    final editingItemId = isEditing ? record.id : null;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              title: Text(isEditing ? 'تعديل الصنف' : 'إضافة صنف جديد'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'أدخل الاسم والوصف بلغة واحدة — الترجمة للغة الأخرى تتم تلقائياً عند الحفظ.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم الصنف (عربي)',
                        helperText: 'يُترجم تلقائياً للإنجليزية إذا تُرك الحقل الإنجليزي فارغاً',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameEnController,
                      decoration: const InputDecoration(
                        labelText: 'Item name (English) — اختياري',
                        helperText: 'أو أدخل الإنجليزية فقط لترجمة العربية تلقائياً',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'الوصف (عربي)',
                        helperText: 'يُترجم تلقائياً عند الحفظ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descEnController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description (English) — optional',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: priceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'السعر النهائي (د.ك)',
                              helperText: 'السعر بعد الخصم إن وُجد',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: costPriceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'تكلفة الطعام / Food Cost (د.ك)',
                              helperText: 'تكلفة المكونات لكل حصة',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        ),
                      ],
                    ),
                    Builder(
                      builder: (context) {
                        final sellingPrice =
                            double.tryParse(priceController.text.trim()) ?? 0;
                        final costPrice =
                            double.tryParse(costPriceController.text.trim());
                        if (sellingPrice <= 0 ||
                            costPrice == null ||
                            costPrice < 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: FoodCostBadge(
                            sellingPrice: sellingPrice,
                            costPrice: costPrice,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: originalPriceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'السعر قبل الخصم (اختياري)',
                        helperText:
                            'يظهر مشطوباً مع شارة الخصم إذا كان أكبر من السعر النهائي',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: categoryController,
                      decoration: const InputDecoration(
                        labelText: 'اسم القسم / التصنيف (عربي)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: imageUrlController,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'مسار الصورة المحلية (اختياري)',
                        hintText: '/menu-images/123456.jpg',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('متوفر للطلب؟'),
                      value: isAvailable,
                      onChanged: (val) =>
                          setDialogState(() => isAvailable = val),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    AdminItemAddonsEditor(
                         options: addonOptions,
                          itemId: int.tryParse(editingItemId?.toString() ?? ''),
                         onChanged: (next) =>
                          setState(() => addonOptions = next),
                          ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    AdminItemLinkedSidesEditor(
                      linkedItemIds: linkedItemIds,
                      currentItemId: int.tryParse(editingItemId?.toString() ?? ''),
                      onChanged: (next) =>
                          setDialogState(() => linkedItemIds = next),
                    ),
                  ],
                ),
              ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.brown,
                  ),
                  onPressed: () async {
                    if ((nameController.text.trim().isEmpty &&
                            nameEnController.text.trim().isEmpty) ||
                        priceController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('يرجى ملء الاسم (عربي أو إنجليزي) والسعر'),
                        ),
                      );
                      return;
                    }

                    final nameAr = nameController.text.trim();
                    final nameEn = nameEnController.text.trim();
                    final descriptionAr = descController.text.trim();
                    final descriptionEn = descEnController.text.trim();

                    final itemMap = <String, dynamic>{
                      'name': nameAr.isNotEmpty ? nameAr : nameEn,
                      'nameAr': nameAr,
                      'nameEn': nameEn,
                      'description':
                          descriptionAr.isNotEmpty ? descriptionAr : descriptionEn,
                      'descriptionAr': descriptionAr,
                      'descriptionEn': descriptionEn,
                      'price': double.tryParse(priceController.text) ?? 0.0,
                      if (costPriceController.text.trim().isNotEmpty)
                        'costPrice':
                            double.tryParse(costPriceController.text.trim()),
                      'originalPrice':
                          double.tryParse(originalPriceController.text.trim()),
                      'categoryName': categoryController.text.trim(),
                      'categoryId': data?['categoryId'] ?? '',
                      'imageUrl': normalizeMenuImageUrl(imageUrlController.text.trim()),
                      'options': addonOptions
                          .where(
                            (option) =>
                                (option['name']?.toString().trim().isNotEmpty ??
                                    false),
                          )
                          .map((option) => Map<String, dynamic>.from(option))
                          .toList(),
                      'linkedItemIds': linkedItemIds,
                      'isAvailable': isAvailable,
                      if (data?['displayOrder'] != null)
                        'displayOrder': data!['displayOrder'],
                    };

                    if (isEditing) {
                      if (AdminAuthService.instance.isLoggedIn) {
                        await ApiService.instance.updateMenuItem(
                          record.id,
                          itemMap,
                        );
                      } else {
                        await MenuStorageService.instance
                            .updateItem(record.id, itemMap);
                      }
                    } else {
                      itemMap['createdAt'] = DateTime.now().toIso8601String();
                      if (AdminAuthService.instance.isLoggedIn) {
                        await ApiService.instance.createMenuItem(itemMap);
                      } else {
                        await MenuStorageService.instance.addItem(itemMap);
                      }
                    }

                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isEditing
                                ? 'تم حفظ الصنف مع الترجمة التلقائية'
                                : 'تمت إضافة الصنف مع الترجمة التلقائية',
                          ),
                        ),
                      );
                    }
                  },
                  child: Text(
                    isEditing ? 'حفظ التعديلات' : 'إضافة الصنف',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteItem(String docId) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تأكيد الحذف'),
            content: const Text(
              'هل أنت تأكد من رغبتك في حذف هذا الصنف من المنيو؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('حذف', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      if (AdminAuthService.instance.isLoggedIn) {
        await ApiService.instance.deleteMenuItem(docId);
      } else {
        await MenuStorageService.instance.deleteItem(docId);
      }
    }
  }

  String get _activeRestaurantId {
    final scoped = SuperAdminScopeService.instance.effectiveRestaurantId;
    if (scoped.isNotEmpty) return scoped;
    return AdminAuthService.instance.restaurantId ?? ApiService.defaultRestaurantId;
  }

  Future<void> _processAndSaveTalabatMenu({
    required String url,
    required void Function(String message) onProgress,
    required void Function(int added, int skipped, int updated) onComplete,
  }) {
    return processAndSaveTalabatMenu(
      url: url,
      restaurantId: _activeRestaurantId,
      onProgress: onProgress,
      onComplete: onComplete,
    );
  }

  void _showAutofillDialog() {
    final urlController = TextEditingController();
    var isLoading = false;
    String? statusMessage;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: const Row(
                children: [
                  Icon(Icons.cloud_download, color: Colors.brown),
                  SizedBox(width: 10),
                  Text(
                    'تعبئة المنيو تلقائياً',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'أدخل رابط Talabat لسحب الأصناف — سيتم حفظ الصور محلياً على السيرفر تلقائياً:',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: urlController,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'رابط المنيو (Talabat URL)',
                        hintText: 'https://www.talabat.com/...',
                        prefixIcon: Icon(Icons.link),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (statusMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        statusMessage!,
                        style: TextStyle(
                          color: statusMessage!.contains('نجاح') ||
                                  statusMessage!.contains('تمت')
                              ? Colors.green
                              : Colors.brown,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.brown,
                  ),
                  icon: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.download, color: Colors.white),
                  label: Text(
                    isLoading ? 'جاري السحب...' : 'بدء التعبئة',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onPressed: isLoading
                      ? null
                      : () async {
                          final url = urlController.text.trim();
                          if (url.isEmpty) {
                            setDialogState(() {
                              statusMessage = 'يرجى إدخال رابط صحيح أولاً';
                            });
                            return;
                          }

                          setDialogState(() {
                            isLoading = true;
                            statusMessage = 'جاري الاتصال وسحب المنيو...';
                          });

                          await _processAndSaveTalabatMenu(
                            url: url,
                            onProgress: (msg) {
                              setDialogState(() => statusMessage = msg);
                            },
                            onComplete: (added, skipped, updated) {
                              setDialogState(() {
                                isLoading = false;
                                if (added > 0 || skipped > 0 || updated > 0) {
                                  statusMessage =
                                      'تمت التعبئة! أُضيف $added، وتم تحديث $updated، وتجاهل $skipped.';
                                } else {
                                  statusMessage =
                                      'لم تُضف أصناف جديدة. جرّب إعادة التعبئة لتحديث الأصناف الحالية.';
                                }
                              });
                              if (mounted) {
                                setState(() => _menuRevision++);
                              }
                            },
                          );
                        },
                ),
              ],
            );
          },
        );
      },
    ).then((_) => urlController.dispose());
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F6F8),
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(28),
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6B1124).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings,
                      size: 52,
                      color: Color(0xFF6B1124),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Almenupro',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6B1124),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'دخول لوحة الإدارة',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const [
                      ButtonSegment(value: 0, label: Text('مدير')),
                      ButtonSegment(value: 2, label: Text('كاشير / مطبخ')),
                      ButtonSegment(value: 1, label: Text('AlMenuPro')),
                    ],
                    selected: {_loginMode},
                    onSelectionChanged: (value) {
                      setState(() {
                        _loginMode = value.first;
                        _errorMessage = null;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  if (_loginMode == 1)
                    TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم المستخدم',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    )
                  else ...[
                    TextField(
                      controller: _slugController,
                      decoration: InputDecoration(
                        labelText: _loginMode == 2
                            ? 'اسم المطعم'
                            : 'معرف المطعم (slug)',
                        hintText: _loginMode == 2
                            ? 'Molton Cookies أو molton-cookies'
                            : 'molton-cookies',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.store),
                      ),
                    ),
                    if (_loginMode == 2) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _cashierNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'اسم المستخدم',
                          hintText: 'اسم الكاشير أو مستخدم المطبخ',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    onSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      labelText: _loginMode == 2 ? 'كلمة المرور / PIN' : 'كلمة المرور',
                      errorText: _errorMessage,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B1124),
                      ),
                      onPressed: _isLoggingIn ? null : _login,
                      child: _isLoggingIn
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              _loginMode == 1
                                  ? 'دخول Super Admin'
                                  : _loginMode == 2
                                      ? 'دخول الكاشير / المطبخ'
                                      : 'دخول لوحة المطعم',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
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

    return Directionality(
      textDirection: TextDirection.rtl,
      child: _buildAuthenticatedShell(),
    );
  }

  bool get _isMenuTabSelected {
    if (_isSuperAdmin) {
      return _selectedIndex == AdminSidebar.superMenuIndex;
    }
    return _selectedIndex == AdminSidebar.menuIndex;
  }

  void _onMenuPanelStatusChanged(AdminMenuPanelStatus status) {
    if (_menuPanelStatus == status) return;
    setState(() => _menuPanelStatus = status);
  }

  Widget _buildMenuSidebarFooter(bool collapsed) {
    final status = _menuPanelStatus;
    if (!_isMenuTabSelected || status == null || status.isHealthy) {
      return const SizedBox.shrink();
    }
    return AdminMenuSidebarFooter(status: status, collapsed: collapsed);
  }

  Widget _buildAuthenticatedShell() {
    if (_isKitchenSession) {
      return KitchenStationScreen(onLogout: _confirmLogout);
    }
    if (_isCashierSession) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F6F8),
        body: SafeArea(
          child: PosShiftShell(
            restaurantId: AdminAuthService.instance.restaurantId,
            tableManagementEnabled: _tableManagementEnabled,
            initialRoute: readPosRouteFromLocation(),
            onOrderSubmitted: () {
              unawaited(OrdersService.instance.refreshOrders());
            },
            onLogout: _confirmLogout,
          ),
        ),
      );
    }

    final sidebarItems = _sidebarItems;

    Widget buildSidebar({required bool inDrawer}) {
      return AdminSidebar(
        items: sidebarItems,
        selectedIndex: _selectedIndex,
        isSuperAdmin: _isSuperAdmin,
        onLogout: _confirmLogout,
        onItemSelected: (index) {
          setState(() => _selectedIndex = index);
          if (inDrawer) {
            Navigator.of(context).maybePop();
          }
        },
        settingsNavIndex: _settingsNavIndex,
        selectedSettingsTab: _selectedIndex == _settingsNavIndex
            ? _activeSettingsTab()
            : null,
        onSettingsSubItemSelected: _openSettingsTab,
        width: inDrawer ? 280 : AdminSidebar.expandedWidth,
        enableCollapse: !inDrawer,
        footerBuilder: inDrawer ? null : _buildMenuSidebarFooter,
      );
    }

    Widget buildShell({required bool mobile}) {
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopHeader(onMenuTap: mobile ? () => _shellScaffoldKey.currentState?.openDrawer() : null),
          if (_shouldShowWhatsappBanner) _buildWhatsappMissingBanner(),
          Expanded(
            child: ListenableBuilder(
              listenable: SuperAdminScopeService.instance,
              builder: (context, _) {
                try {
                  return SizedBox.expand(child: _buildActiveTab());
                } catch (error) {
                  return AppErrorBoundary.releaseFallback(
                    FlutterErrorDetails(exception: error),
                    onRetry: () => setState(() {}),
                  );
                }
              },
            ),
          ),
        ],
      );

      if (mobile) {
        return Scaffold(
          key: _shellScaffoldKey,
          backgroundColor: const Color(0xFFF4F6F8),
          drawer: Drawer(
            width: 280,
            backgroundColor: AdminSidebar.sidebarBg,
            child: SafeArea(child: buildSidebar(inDrawer: true)),
          ),
          body: SafeArea(child: content),
        );
      }

      return Scaffold(
        backgroundColor: const Color(0xFFF4F6F8),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildSidebar(inDrawer: false),
            Expanded(child: content),
          ],
        ),
      );
    }

    final shell = LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 900;
        return buildShell(mobile: mobile);
      },
    );

    if (_isSuperAdmin) return shell;

    return Listener(
      onPointerDown: (_) {
        OrderAlertSoundService.instance.unlockFromUserGesture();
      },
      child: shell,
    );
  }

  List<Widget> get _menuHeaderActions {
    if (!_isMenuTabSelected) return const [];
    final canImport = !_isSuperAdmin || SuperAdminScopeService.instance.hasSelection;
    return [
      OutlinedButton.icon(
        onPressed: canImport ? _showAutofillDialog : null,
        icon: const Icon(Icons.cloud_download_outlined, size: 18),
        label: const Text('جلب المنيو من طلبات'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF6B1124),
          side: const BorderSide(color: Color(0xFF6B1124)),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
      FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF6B1124),
          foregroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onPressed: () => _showItemDialog(),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('إضافة صنف جديد'),
      ),
    ];
  }

  Widget _buildTopHeader({VoidCallback? onMenuTap}) {
    if (_isSuperAdmin) {
      return AdminTopHeader(
        isSuperAdmin: true,
        showOrderNotifications: false,
        restaurantLabel: _restaurantLabel,
        onMenuTap: onMenuTap,
        onLogout: _confirmLogout,
        actions: _menuHeaderActions,
      );
    }

    return ValueListenableBuilder<int>(
      valueListenable: AdminOrderMonitorService.instance.pendingCount,
      builder: (context, pendingCount, _) {
        return AdminTopHeader(
          isSuperAdmin: false,
          showOrderNotifications: true,
          restaurantLabel: _restaurantLabel,
          pendingOrdersCount: pendingCount,
          onMenuTap: onMenuTap,
          onLogout: _confirmLogout,
          actions: _menuHeaderActions,
          onNotificationsTap: () {
            setState(() => _selectedIndex = AdminSidebar.ordersIndex);
            _ordersPanelKey.currentState?.selectNewOrdersTab();
          },
        );
      },
    );
  }

  Widget _buildDeliveryZonesPanel() {
    final scope = SuperAdminScopeService.instance;
    final restaurantId = scope.effectiveRestaurantId;
    final canManage =
        !_isSuperAdmin || scope.hasSelection;

    return AdminDeliveryZonesPanel(
      key: ValueKey('delivery-zones-$restaurantId'),
      restaurantId: restaurantId,
      canManage: canManage,
      kitchenManagementEnabled: _kitchenManagementEnabled,
    );
  }

  Widget _buildOffersPanel() {
    final scope = SuperAdminScopeService.instance;
    final restaurantId = scope.effectiveRestaurantId;
    final canManage = !_isSuperAdmin || scope.hasSelection;

    return AdminOffersPanel(
      key: ValueKey('offers-$restaurantId'),
      restaurantId: restaurantId,
      canManage: canManage,
    );
  }

  Widget _buildPosTab() {
    final scope = SuperAdminScopeService.instance;
    if (_isSuperAdmin && !scope.hasSelection) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'اختر مطعماً من تبويب المطاعم أولاً لفتح نقطة البيع.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    return PosShiftShell(
      key: ValueKey('pos-${scope.effectiveRestaurantId}'),
      restaurantId: scope.effectiveRestaurantId,
      tableManagementEnabled: _tableManagementEnabled,
      initialRoute: readPosRouteFromLocation(),
      onOrderSubmitted: () {
        unawaited(OrdersService.instance.refreshOrders());
      },
      onLogout: _confirmLogout,
      onOpenMenu: () {
        setState(() {
          _selectedIndex = _isSuperAdmin
              ? AdminSidebar.superMenuIndex
              : AdminSidebar.menuIndex;
        });
      },
    );
  }

  Widget _buildStaffTab() {
    return ListenableBuilder(
      listenable: SuperAdminScopeService.instance,
      builder: (context, _) {
        return ListenableBuilder(
          listenable: PosOperationsService.instance,
          builder: (context, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'الموظفين والكاشير',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6B1124),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isSuperAdmin
                        ? 'عرض موظفي كل مطعم من قاعدة البيانات. اختر مطعماً لإضافة موظف أو تعديل الصلاحيات.'
                        : 'موظفون وكاشير هذا المطعم من قاعدة البيانات، مع إضافة موظف وتسجيل الدخول.',
                  ),
                  const SizedBox(height: 20),
                  if (!_isSuperAdmin ||
                      SuperAdminScopeService.instance.hasSelection)
                    PosCashierLoginPanel(
                      compact: true,
                      onLoggedIn: () => setState(() {}),
                    ),
                  if (!_isSuperAdmin ||
                      SuperAdminScopeService.instance.hasSelection)
                    const SizedBox(height: 20),
                  AdminPosRolesStaffCard(
                    key: ValueKey(
                      SuperAdminScopeService.instance.selectedRestaurantId ??
                          'all-staff',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActiveTab() {
    if (_isKitchenSession) {
      return KitchenStationScreen(onLogout: _confirmLogout);
    }
    if (_isCashierSession) {
      return _buildPosTab();
    }
    if (_isSuperAdmin) {
      switch (_selectedIndex) {
        case AdminSidebar.superPosIndex:
          return _buildPosTab();
        case AdminSidebar.superMenuIndex:
          return AdminMenuPanel(
            key: ValueKey(
              '${SuperAdminScopeService.instance.selectedRestaurantId ?? 'super-menu-none'}-$_menuRevision',
            ),
            restaurantId:
                SuperAdminScopeService.instance.effectiveRestaurantId,
            onAddItem: () => _showItemDialog(),
            onEditItem: (record) => _showItemDialog(record: record),
            onDeleteItem: _deleteItem,
            canImportTalabat: SuperAdminScopeService.instance.hasSelection,
            onAutofillTalabat: SuperAdminScopeService.instance.hasSelection
                ? _showAutofillDialog
                : null,
            canManageItems: SuperAdminScopeService.instance.hasSelection,
            onStatusChanged: _onMenuPanelStatusChanged,
          );
        case AdminSidebar.superRestaurantsIndex:
          return const AdminSuperRestaurantsPanel();
        case AdminSidebar.superDeliveryZonesIndex:
          return _buildDeliveryZonesPanel();
        case AdminSidebar.superOffersIndex:
          return _buildOffersPanel();
        case AdminSidebar.superAnalyticsIndex:
          return _buildAnalyticsTab();
        case AdminSidebar.superSmartUpsellIndex:
          return const AdminSmartUpsellPanel();
        case AdminSidebar.superStaffIndex:
          return _buildStaffTab();
        case AdminSidebar.superReviewsIndex:
          return const AdminReviewsPanel();
        case AdminSidebar.superExpensesIndex:
          return const AdminExpensesPanel();
        case AdminSidebar.superSettingsIndex:
          return AdminSettingsTabbedPanel(
            isSuperAdmin: true,
            activeTab: _activeSettingsTab(),
            restaurantLabel: _restaurantLabel,
          );
        case AdminSidebar.superTablesIndex:
          return const AdminTablesPanel();
        default:
          return _buildDeliveryZonesPanel();
      }
    }

    switch (_selectedIndex) {
      case AdminSidebar.ordersIndex:
        return AdminOrdersPanel(key: _ordersPanelKey);
      case AdminSidebar.customersIndex:
        return const AdminCustomersPanel();
      case AdminSidebar.menuIndex:
        return AdminMenuPanel(
          key: ValueKey(
            '${SuperAdminScopeService.instance.effectiveRestaurantId}-$_menuRevision',
          ),
          restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
          onAddItem: () => _showItemDialog(),
          onEditItem: (record) => _showItemDialog(record: record),
          onDeleteItem: _deleteItem,
          canImportTalabat: true,
          onAutofillTalabat: _showAutofillDialog,
          canManageItems: true,
          onStatusChanged: _onMenuPanelStatusChanged,
        );
      case AdminSidebar.deliveryZonesIndex:
        return _buildDeliveryZonesPanel();
      case AdminSidebar.offersIndex:
        return _buildOffersPanel();
      case AdminSidebar.analyticsIndex:
        return _buildAnalyticsTab();
      case AdminSidebar.smartUpsellIndex:
        return const AdminSmartUpsellPanel();
      case AdminSidebar.staffIndex:
        return _buildStaffTab();
      case AdminSidebar.reviewsIndex:
        return const AdminReviewsPanel();
      case AdminSidebar.expensesIndex:
        return const AdminExpensesPanel();
      case AdminSidebar.settingsIndex:
        return AdminSettingsTabbedPanel(
          isSuperAdmin: false,
          activeTab: _activeSettingsTab(),
          restaurantLabel: _restaurantLabel,
        );
      case AdminSidebar.tablesIndex:
        return const AdminTablesPanel();
      case AdminSidebar.posIndex:
        return _buildPosTab();
      default:
        return AdminOrdersPanel(key: _ordersPanelKey);
    }
  }

  Widget _buildWhatsappMissingBanner() {
    return Material(
      color: const Color(0xFFFFF3E0),
      child: InkWell(
        onTap: () => _openSettingsTab(AdminSettingsTab.whatsapp),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.orange.shade300, width: 1.5),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 640;
              final configureButton = FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6B1124),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                onPressed: () => _openSettingsTab(AdminSettingsTab.whatsapp),
                icon: const Icon(Icons.settings, size: 18),
                label: const Text('إعدادات الواتساب'),
              );

              final message = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'رقم الواتساب غير مُعيَّن',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.orange.shade900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'أدخل رقم واتساب المطعم في الإعدادات لاستقبال طلبات العملاء بنجاح.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange.shade900,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: message),
                      ],
                    ),
                    const SizedBox(height: 12),
                    configureButton,
                  ],
                );
              }

              return Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange.shade900,
                    size: 30,
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: message),
                  const SizedBox(width: 12),
                  configureButton,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildWhatsappStatusCard() {
    final configured = _whatsappConfigured;
    final savedDisplay = configured
        ? WhatsAppPhone.formatDisplay(
            _loadedSettings!.whatsappCountryCode,
            _loadedSettings!.whatsappPhone,
          )
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: configured ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: configured ? Colors.green.shade400 : Colors.red.shade300,
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            configured ? Icons.check_circle : Icons.error_outline,
            color: configured ? Colors.green.shade700 : Colors.red.shade700,
            size: 34,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  configured ? 'رقم الواتساب مُفعَّل' : 'لم يُعيَّن رقم واتساب بعد',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: configured
                        ? Colors.green.shade900
                        : Colors.red.shade900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  configured
                      ? 'الرقم المحفوظ حالياً في قاعدة البيانات:\n$savedDisplay'
                      : 'الطلبات لن تُرسل للعملاء حتى تحفظ رقم واتساب المطعم أدناه.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: configured
                        ? Colors.green.shade800
                        : Colors.red.shade800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    final scope = SuperAdminScopeService.instance;
    final restaurantLabel = _isSuperAdmin
        ? (scope.selectedRestaurantName ?? '—')
        : (_restaurantLabel ?? 'المطعم');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'إعدادات المطعم — رقم الواتساب',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6B1124),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isSuperAdmin
                ? 'المطعم الحالي: $restaurantLabel — حدد رقم الواتساب الذي يستقبل طلبات هذا المطعم:'
                : 'حدد رقم الواتساب الذي يستقبل طلبات وفواتير عملاء مطعمك:',
          ),
          const SizedBox(height: 6),
          Text(
            'يجب حفظ رقم واتساب هنا ليتمكن العملاء من إرسال الطلبات.',
            style: TextStyle(
              color: Colors.red.shade700,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          if (_isSuperAdmin && !scope.hasSelection) ...[
            const SizedBox(height: 12),
            const Text(
              'اختر مطعماً من قائمة «المطاعم» أولاً لضبط رقم الواتساب الخاص به.',
              style: TextStyle(color: Colors.orange),
            ),
          ],
          const SizedBox(height: 20),
          _buildWhatsappStatusCard(),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'تعديل رقم الواتساب',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 150,
                        child: DropdownButtonFormField<String>(
                          initialValue: _whatsappCountryCode,
                          decoration: const InputDecoration(
                            labelText: 'مفتاح الدولة',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                          ),
                          items: WhatsAppPhone.countryCodes
                              .map(
                                (entry) => DropdownMenuItem(
                                  value: entry.$1,
                                  child: Text(entry.$2),
                                ),
                              )
                              .toList(),
                          onChanged: (_isSuperAdmin && !scope.hasSelection)
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setState(() => _whatsappCountryCode = value);
                                },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _whatsappController,
                          enabled: !_isSuperAdmin || scope.hasSelection,
                          keyboardType: TextInputType.phone,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'رقم الواتساب',
                            hintText: 'مثال: 94774950',
                            prefixIcon: Icon(Icons.phone, color: Colors.green),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'سيُستخدم الرقم: ${WhatsAppPhone.formatDisplay(_whatsappCountryCode, _whatsappController.text)}',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.brown,
                      ),
                      onPressed: (_isSavingSettings ||
                              (_isSuperAdmin && !scope.hasSelection))
                          ? null
                          : _saveWhatsappNumber,
                      icon: _isSavingSettings
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.save, color: Colors.white),
                      label: const Text(
                        'حفظ الرقم الآن',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const AdminWorkingHoursCard(),
          if (!_isSuperAdmin) ...[
            const SizedBox(height: 20),
            const AdminSoundSettingsCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    return const AdminAnalyticsReportsPanel();
  }
}
