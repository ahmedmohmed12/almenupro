import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/order.dart';
import '../models/restaurant_settings.dart';
import '../models/staff_user.dart';
import '../l10n/app_strings.dart';
import '../utils/admin_deep_link.dart';
import '../utils/admin_route_nav.dart';
import '../utils/admin_settings_url.dart';
import '../utils/firebase_config.dart';
import '../utils/food_cost_utils.dart';
import '../utils/image_url.dart';
import '../utils/whatsapp_phone.dart';
import '../services/admin_auth_service.dart';
import '../services/scheduled_kitchen_release.dart';
import '../services/scheduled_orders_controller.dart';
import '../services/scheduled_release_engine.dart';
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
import '../utils/talabat_manual_menu_json.dart';
import '../widgets/admin/admin_analytics_reports_panel.dart';
import '../widgets/admin/admin_corner_toast.dart';
import '../widgets/admin/admin_pos_roles_staff_card.dart';
import '../widgets/admin/pos/pos_cashier_login_panel.dart';
import '../widgets/admin/pos/pos_shift_shell.dart';
import '../widgets/admin/kitchen_station_screen.dart';
import '../widgets/admin/driver_station_screen.dart';
import '../widgets/admin/admin_delivery_zones_panel.dart';
import '../widgets/admin/admin_drivers_panel.dart';
import '../widgets/admin/admin_offers_panel.dart';
import '../widgets/admin/admin_reviews_panel.dart';
import '../widgets/admin/admin_expenses_panel.dart';
import '../widgets/admin/admin_item_addons_editor.dart';
import '../widgets/admin/admin_item_linked_sides_editor.dart';
import '../widgets/admin/admin_menu_panel.dart';
import '../widgets/admin/admin_platform_menu_mapping_panel.dart';
import '../widgets/admin/admin_orders_panel.dart';
import '../widgets/admin/admin_customers_panel.dart';
import '../widgets/admin/smart_whatsapp_hub_page.dart';
import '../widgets/admin/hr/hr_module_page.dart';
import '../widgets/admin/scheduled_orders_page.dart';
import '../utils/whatsapp_launcher.dart';
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
import 'auth/manager_login_screen.dart';

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
  String? _restaurantLabel;
  int _selectedIndex = AdminSidebar.analyticsIndex;
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
        AdminSidebar.whatsappBroadcastItem,
        AdminSidebar.reservationsItem,
        AdminSidebar.hrItem,
        if (SuperAdminScopeService.instance.hasSelection &&
            _tableManagementEnabled)
          AdminSidebar.tablesItem,
      ];
    }
    return [
      ...AdminSidebar.defaultItems,
      AdminSidebar.whatsappBroadcastItem,
      AdminSidebar.reservationsItem,
      AdminSidebar.hrItem,
      if (_tableManagementEnabled) AdminSidebar.tablesItem,
    ];
  }

  bool get _isCashierSession => AdminAuthService.instance.isCashier;
  bool get _isKitchenSession => AdminAuthService.instance.isKitchen;
  bool get _isDriverSession => AdminAuthService.instance.isDriver;

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
    if (_isCashierSession || _isKitchenSession || _isDriverSession)
      return false;
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
    ScheduledOrdersController.instance.addListener(_onScheduledDesk);
    unawaited(ScheduledOrdersController.instance.start());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScheduledDesk();
    });
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
        _selectedIndex =
            AdminAuthService.instance.isCashier ||
                AdminAuthService.instance.isKitchen ||
                AdminAuthService.instance.isDriver
            ? 0
            : (_isSuperAdmin
                  ? AdminSidebar.superAnalyticsIndex
                  : AdminSidebar.analyticsIndex);
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
    final redirect =
        AdminDeepLink.parseRedirect(uri) ??
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
    final redirect =
        AdminDeepLink.parseRedirect(uri) ??
        AdminOrderFocusService.instance.consumeRedirect() ??
        AdminDeepLink.sanitizeRedirect(readStoredAdminRedirect());
    clearStoredAdminRedirect();

    final orderRef =
        AdminDeepLink.parseOrderRef(uri) ??
        (redirect == null
            ? null
            : AdminDeepLink.parseOrderRef(Uri.parse(redirect)));
    if (orderRef == null) return;

    replaceAdminPath(AdminDeepLink.orderPath(orderRef));
    AdminOrderFocusService.instance.requestOrder(orderRef);
    unawaited(OrdersService.instance.refreshOrders());
    if (_isCashierSession ||
        _isKitchenSession ||
        _isDriverSession ||
        _isSuperAdmin) {
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
    ScheduledOrdersController.instance.removeListener(_onScheduledDesk);
    _whatsappController.dispose();
    super.dispose();
  }

  void _onScheduledDesk() {
    final actions = ScheduledOrdersController.instance.drainActions();
    for (final action in actions) {
      switch (action.kind) {
        case ScheduledDeskActionKind.kitchenRelease:
          unawaited(dispatchScheduledKitchenRelease(action.order));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('حان وقت الطباعة: الطلب المجدول دخل المطبخ.'),
              ),
            );
          }
        case ScheduledDeskActionKind.whatsappReminder:
          unawaited(
            openWhatsAppChat(
              phone: action.order.phone,
              message: scheduledReminderText(action.order),
            ),
          );
        case ScheduledDeskActionKind.driverNotice:
          break;
      }
    }
  }

  Future<void> _loadSettings() async {
    try {
      final restaurantId =
          SuperAdminScopeService.instance.effectiveRestaurantId;
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
            ? AdminSidebar.superAnalyticsIndex
            : AdminSidebar.analyticsIndex;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('يرجى إدخال رقم الواتساب')));
      return;
    }
    setState(() => _isSavingSettings = true);

    try {
      final restaurantId =
          SuperAdminScopeService.instance.effectiveRestaurantId;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر حفظ رقم الواتساب: $error')));
    } finally {
      if (mounted) setState(() => _isSavingSettings = false);
    }
  }

  Future<void> _onExternalLoginSuccess() async {
    if (!mounted) return;
    setState(() {
      _isAuthenticated = true;
      _isSuperAdmin = AdminAuthService.instance.isSuperAdmin;
      _restaurantLabel = AdminAuthService.instance.restaurantName;
      _selectedIndex =
          AdminAuthService.instance.isCashier ||
              AdminAuthService.instance.isKitchen ||
              AdminAuthService.instance.isDriver
          ? 0
          : (_isSuperAdmin
              ? AdminSidebar.superAnalyticsIndex
              : AdminSidebar.analyticsIndex);
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
  }

  Future<void> _confirmLogout() async {
    final s = AppStrings.read(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(s.tr('تسجيل الخروج', 'Log out')),
          content: Text(
            s.tr(
              'هل تريد تسجيل الخروج من لوحة التحكم؟',
              'Do you want to log out of the dashboard?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6B1124),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.tr('تسجيل الخروج', 'Log out')),
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
    replaceAdminPath(AdminDeepLink.managerLoginPath);
    if (!mounted) return;
    setState(() {
      _isAuthenticated = false;
      _isSuperAdmin = false;
      _restaurantLabel = null;
      _selectedIndex = AdminSidebar.analyticsIndex;
    });
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AdminDeepLink.managerLoginPath);
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
          roleId: stored?.roleId.isNotEmpty == true
              ? stored!.roleId
              : 'cashier',
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
            child: const Text(
              'تفعيل الإشعارات',
              style: TextStyle(color: Colors.white),
            ),
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
      text:
          data?['nameAr']?.toString() ??
          data?['name_ar']?.toString() ??
          data?['name']?.toString() ??
          '',
    );
    final nameEnController = TextEditingController(
      text: data?['nameEn']?.toString() ?? data?['name_en']?.toString() ?? '',
    );
    final descController = TextEditingController(
      text:
          data?['descriptionAr']?.toString() ??
          data?['description_ar']?.toString() ??
          data?['description']?.toString() ??
          '',
    );
    final descEnController = TextEditingController(
      text:
          data?['descriptionEn']?.toString() ??
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
      text: (data?['originalPrice'] ?? data?['original_price'] ?? '')
          .toString(),
    );
    final categoryController = TextEditingController(
      text: data?['categoryName'] ?? 'أشهر الأصناف',
    );
    final imageUrlController = TextEditingController(
      text: normalizeMenuImageUrl(data?['imageUrl'] as String?),
    );
    final videoWebmController = TextEditingController(
      text: (data?['videoUrlWebm'] ?? data?['video_url_webm'] ?? '').toString(),
    );
    final videoMp4Controller = TextEditingController(
      text: (data?['videoUrlMp4'] ?? data?['video_url_mp4'] ?? '').toString(),
    );
    var isStory =
        data?['isStory'] == true ||
        data?['is_story'] == true ||
        data?['isStory'] == 1 ||
        data?['is_story'] == 1;
    var isAvailable = data?['isAvailable'] as bool? ?? true;
    final showOnWebsiteRaw = data?['showOnWebsite'] ?? data?['show_on_website'];
    var showOnWebsite =
        showOnWebsiteRaw != false &&
        showOnWebsiteRaw != 0 &&
        showOnWebsiteRaw != '0' &&
        showOnWebsiteRaw != 'false';
    var addonOptions = (data?['options'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
    var linkedItemIds =
        (data?['linkedItemIds'] as List<dynamic>? ??
                data?['linked_item_ids'] as List<dynamic>? ??
                [])
            .map((id) => int.tryParse(id.toString()))
            .whereType<int>()
            .toList();
    final editingItemId = isEditing ? record.id : null;
    var saving = false;

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
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF666666),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'اسم الصنف (عربي)',
                          helperText:
                              'يُترجم تلقائياً للإنجليزية إذا تُرك الحقل الإنجليزي فارغاً',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameEnController,
                        decoration: const InputDecoration(
                          labelText: 'Item name (English) — اختياري',
                          helperText:
                              'أو أدخل الإنجليزية فقط لترجمة العربية تلقائياً',
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
                              keyboardType:
                                  const TextInputType.numberWithOptions(
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
                              keyboardType:
                                  const TextInputType.numberWithOptions(
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
                          final costPrice = double.tryParse(
                            costPriceController.text.trim(),
                          );
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
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
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
                      TextField(
                        controller: videoWebmController,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'رابط فيديو WebM (اختياري)',
                          helperText:
                              'يُحمّل فقط عندما يضغط العميل على المشاهدة',
                          hintText: 'https://cdn.example.com/dish.webm',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: videoMp4Controller,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'رابط فيديو MP4 احتياطي (اختياري)',
                          hintText: 'https://cdn.example.com/dish.mp4',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SwitchListTile(
                        title: const Text('إظهار ضمن القصص المميزة'),
                        subtitle: const Text('يتطلب صورة وفيديو صالحين للصنف'),
                        value: isStory,
                        onChanged: (val) => setDialogState(() => isStory = val),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('متوفر للطلب؟'),
                        subtitle: const Text(
                          'إذا أُغلق يختفي من الكاشير والموقع',
                        ),
                        value: isAvailable,
                        onChanged: (val) =>
                            setDialogState(() => isAvailable = val),
                      ),
                      SwitchListTile(
                        title: const Text('يظهر في الموقع الإلكتروني؟'),
                        subtitle: const Text(
                          'إذا أُغلق يبقى ظاهراً للكاشير فقط ولا يظهر للعملاء',
                        ),
                        value: showOnWebsite,
                        onChanged: (val) =>
                            setDialogState(() => showOnWebsite = val),
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
                        currentItemId: int.tryParse(
                          editingItemId?.toString() ?? '',
                        ),
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
                  onPressed: saving
                      ? null
                      : () async {
                          if ((nameController.text.trim().isEmpty &&
                                  nameEnController.text.trim().isEmpty) ||
                              priceController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'يرجى ملء الاسم (عربي أو إنجليزي) والسعر',
                                ),
                              ),
                            );
                            return;
                          }

                          setDialogState(() => saving = true);
                          try {
                            final nameAr = nameController.text.trim();
                            final nameEn = nameEnController.text.trim();
                            final descriptionAr = descController.text.trim();
                            final descriptionEn = descEnController.text.trim();

                            final itemMap = <String, dynamic>{
                              'name': nameAr.isNotEmpty ? nameAr : nameEn,
                              'nameAr': nameAr,
                              'nameEn': nameEn,
                              'description': descriptionAr.isNotEmpty
                                  ? descriptionAr
                                  : descriptionEn,
                              'descriptionAr': descriptionAr,
                              'descriptionEn': descriptionEn,
                              'price':
                                  double.tryParse(priceController.text) ?? 0.0,
                              if (costPriceController.text.trim().isNotEmpty)
                                'costPrice': double.tryParse(
                                  costPriceController.text.trim(),
                                ),
                              'originalPrice': double.tryParse(
                                originalPriceController.text.trim(),
                              ),
                              'categoryName': categoryController.text.trim(),
                              'categoryId': data?['categoryId'] ?? '',
                              'imageUrl': normalizeMenuImageUrl(
                                imageUrlController.text.trim(),
                              ),
                              'videoUrlWebm': videoWebmController.text.trim(),
                              'videoUrlMp4': videoMp4Controller.text.trim(),
                              'isStory': isStory,
                              'options': addonOptions
                                  .where(
                                    (option) =>
                                        (option['name']
                                            ?.toString()
                                            .trim()
                                            .isNotEmpty ??
                                        false),
                                  )
                                  .map(
                                    (option) =>
                                        Map<String, dynamic>.from(option),
                                  )
                                  .toList(),
                              'linkedItemIds': linkedItemIds,
                              'isAvailable': isAvailable,
                              'showOnWebsite': showOnWebsite,
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
                                await MenuStorageService.instance.updateItem(
                                  record.id,
                                  itemMap,
                                );
                              }
                            } else {
                              itemMap['createdAt'] = DateTime.now()
                                  .toIso8601String();
                              if (AdminAuthService.instance.isLoggedIn) {
                                await ApiService.instance.createMenuItem(
                                  itemMap,
                                );
                              } else {
                                await MenuStorageService.instance.addItem(
                                  itemMap,
                                );
                              }
                            }

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    isEditing
                                        ? 'تم حفظ الصنف'
                                        : 'تمت إضافة الصنف',
                                  ),
                                ),
                              );
                            }
                          } catch (error) {
                            if (context.mounted) {
                              setDialogState(() => saving = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    error.toString().replaceFirst(
                                      'Exception: ',
                                      '',
                                    ),
                                  ),
                                ),
                              );
                            }
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
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
    final confirm =
        await showDialog<bool>(
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
    return AdminAuthService.instance.restaurantId ??
        ApiService.defaultRestaurantId;
  }

  Future<bool> _processAndSaveTalabatMenu({
    required String url,
    required void Function(String message) onProgress,
    required void Function(int added, int skipped, int updated) onComplete,
    String? talabatCookie,
    String? menuJson,
  }) {
    return processAndSaveTalabatMenu(
      url: url,
      restaurantId: _activeRestaurantId,
      onProgress: onProgress,
      onComplete: onComplete,
      talabatCookie: talabatCookie,
      menuJson: menuJson,
      nextData: menuJson,
    );
  }

  Future<void> _copyTalabatBookmarklet() async {
    try {
      final code = await rootBundle.loadString(
        'web/talabat_menu_bookmarklet.txt',
      );
      await Clipboard.setData(ClipboardData(text: code.trim()));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم النسخ — أنشئ مفضلة جديدة، الصق في «العنوان»، واحفظها: سحب منيو Talabat',
          ),
          duration: Duration(seconds: 6),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحميل أداة السحب')),
      );
    }
  }

  void _showAutofillDialog() {
    final urlController = TextEditingController();
    final pasteController = TextEditingController();
    var isLoading = false;
    String? statusMessage;
    var statusOk = false;

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
                  Icon(Icons.restaurant_menu, color: Colors.brown),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'تعبئة المنيو من Talabat',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '① انسخ أداة السحب إلى المفضلة (مرة واحدة)\n'
                        '② افتح منيو مطعمك على موقع Talabat\n'
                        '③ اضغط الأداة في المفضلة — ستُنسخ البيانات تلقائياً\n'
                        '④ ارجع هنا والصق واضغط «بدء التعبئة»',
                        style: TextStyle(fontSize: 13, height: 1.45),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _copyTalabatBookmarklet,
                        icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                        label: const Text('نسخ أداة السحب إلى المفضلة'),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: urlController,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'رابط صفحة المطعم (اختياري)',
                          hintText: 'يُملأ تلقائياً عند السحب من Talabat',
                          prefixIcon: Icon(Icons.link),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: pasteController,
                        minLines: 4,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          labelText: 'البيانات المنسوخة من Talabat',
                          hintText: 'الصق هنا بعد الضغط على أداة السحب',
                          prefixIcon: Icon(Icons.content_paste_go),
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      if (statusMessage != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: statusOk
                                ? Colors.green.shade50
                                : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: statusOk
                                  ? Colors.green.shade200
                                  : Colors.orange.shade200,
                            ),
                          ),
                          child: Text(
                            statusMessage!,
                            style: TextStyle(
                              color: statusOk
                                  ? Colors.green.shade900
                                  : Colors.brown.shade800,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(ctx),
                  child: const Text('إغلاق'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
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
                      : const Icon(Icons.play_arrow),
                  label: Text(isLoading ? 'جاري التعبئة…' : 'بدء التعبئة'),
                  onPressed: isLoading
                      ? null
                      : () async {
                          final paste = pasteController.text.trim();
                          var url = urlController.text.trim();
                          if (paste.isEmpty && url.isEmpty) {
                            setDialogState(() {
                              statusOk = false;
                              statusMessage =
                                  'الصق البيانات المنسوخة من Talabat أو أدخل الرابط.';
                            });
                            return;
                          }
                          if (url.isEmpty && paste.isNotEmpty) {
                            url = menuUrlFromManualTalabatJson(paste) ?? url;
                          }

                          setDialogState(() {
                            isLoading = true;
                            statusOk = false;
                            statusMessage = 'جاري إضافة الأصناف…';
                          });

                          final ok = await _processAndSaveTalabatMenu(
                            url: url,
                            menuJson: paste.isEmpty ? null : paste,
                            onProgress: (msg) {
                              setDialogState(() {
                                statusOk = false;
                                statusMessage = msg;
                              });
                            },
                            onComplete: (added, skipped, updated) {
                              setDialogState(() {
                                statusOk = true;
                                final total = added + updated;
                                var msg =
                                    'انتهى بنجاح.\n'
                                    'أُضيف $added صنفاً جديداً، وتم تحديث $updated، '
                                    'والمجموع المُعالَج: $total صنف.';
                                if (skipped > 0) {
                                  msg = '$msg\n(تجاهل $skipped)';
                                }
                                statusMessage = msg;
                              });
                              if (mounted) {
                                setState(() => _menuRevision++);
                              }
                            },
                          );
                          setDialogState(() {
                            isLoading = false;
                            if (!ok && !statusOk) {
                              if (statusMessage == null ||
                                  statusMessage!.contains('جاري')) {
                                statusMessage =
                                    'لم تنجح التعبئة. تأكد أنك لصقت البيانات كاملة بعد أداة السحب.';
                              }
                            }
                          });
                        },
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      urlController.dispose();
      pasteController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    if (!_isAuthenticated) {
      final redirect =
          AdminDeepLink.parseRedirect(_locationUri) ??
          AdminDeepLink.sanitizeRedirect(readStoredAdminRedirect());
      return ManagerLoginScreen(
        redirect: redirect,
        onAuthenticated: _onExternalLoginSuccess,
      );
    }

    return Directionality(
      textDirection: s.isArabic ? TextDirection.rtl : TextDirection.ltr,
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
    if (_isDriverSession) {
      return DriverStationScreen(onLogout: _confirmLogout);
    }
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
          _buildTopHeader(
            onMenuTap: mobile
                ? () => _shellScaffoldKey.currentState?.openDrawer()
                : null,
          ),
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
    final s = AppStrings.of(context);
    if (!_isMenuTabSelected) return const [];
    final canImport =
        !_isSuperAdmin || SuperAdminScopeService.instance.hasSelection;
    return [
      OutlinedButton.icon(
        onPressed: canImport ? _showAutofillDialog : null,
        icon: const Icon(Icons.cloud_download_outlined, size: 18),
        label: Text(s.tr('جلب المنيو من طلبات', 'Import menu from Talabat')),
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
        label: Text(s.tr('إضافة صنف جديد', 'Add new item')),
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
    final canManage = !_isSuperAdmin || scope.hasSelection;

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
    final s = AppStrings.of(context);
    final scope = SuperAdminScopeService.instance;
    if (_isSuperAdmin && !scope.hasSelection) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            s.tr(
              'اختر مطعماً من تبويب المطاعم أولاً لفتح نقطة البيع.',
              'Select a restaurant first to open POS.',
            ),
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
    final s = AppStrings.of(context);
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
                  Text(
                    s.tr('الموظفين والكاشير', 'Staff & Cashiers'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6B1124),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isSuperAdmin
                        ? s.tr(
                            'عرض موظفي كل مطعم من قاعدة البيانات. اختر مطعماً لإضافة موظف أو تعديل الصلاحيات.',
                            'View each restaurant’s staff. Select a restaurant to add staff or edit permissions.',
                          )
                        : s.tr(
                            'موظفون وكاشير هذا المطعم من قاعدة البيانات، مع إضافة موظف وتسجيل الدخول.',
                            'Manage this restaurant’s staff and cashier accounts.',
                          ),
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
    if (_isDriverSession) {
      return DriverStationScreen(onLogout: _confirmLogout);
    }
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
            restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
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
        case AdminSidebar.superPlatformMappingIndex:
          return AdminPlatformMenuMappingPanel(
            restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
            canManage: SuperAdminScopeService.instance.hasSelection,
          );
        case AdminSidebar.superRestaurantsIndex:
          return const AdminSuperRestaurantsPanel();
        case AdminSidebar.superDeliveryZonesIndex:
          return _buildDeliveryZonesPanel();
        case AdminSidebar.superDriversIndex:
          return const AdminDriversPanel();
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
        case AdminSidebar.superWhatsappBroadcastIndex:
          return const SmartWhatsappHubPage();
        case AdminSidebar.superReservationsIndex:
          return const ScheduledOrdersPage();
        case AdminSidebar.superHrIndex:
          return const HrModulePage();
        case AdminSidebar.superTablesIndex:
          return const AdminTablesPanel();
        default:
          return _buildAnalyticsTab();
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
      case AdminSidebar.platformMappingIndex:
        return AdminPlatformMenuMappingPanel(
          restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
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
      case AdminSidebar.whatsappBroadcastIndex:
        return const SmartWhatsappHubPage();
      case AdminSidebar.reservationsIndex:
        return const ScheduledOrdersPage();
      case AdminSidebar.hrIndex:
        return const HrModulePage();
      case AdminSidebar.tablesIndex:
        return const AdminTablesPanel();
      case AdminSidebar.posIndex:
        return _buildPosTab();
      default:
        return _buildAnalyticsTab();
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
                  configured
                      ? 'رقم الواتساب مُفعَّل'
                      : 'لم يُعيَّن رقم واتساب بعد',
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
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                      onPressed:
                          (_isSavingSettings ||
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
    final hrIndex = _isSuperAdmin
        ? AdminSidebar.superHrIndex
        : AdminSidebar.hrIndex;
  final canReview =
        AdminAuthService.instance.isRestaurantAdmin ||
        AdminAuthService.instance.isSuperAdmin ||
        PosOperationsService.instance.canReviewRemoteApprovals();
    return AdminAnalyticsReportsPanel(
      onOpenHr: () => setState(() => _selectedIndex = hrIndex),
      showKitchenVoidTab: canReview,
    );
  }
}
