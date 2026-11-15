import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_strings.dart';
import '../../../models/pos_role.dart';
import '../../../models/shift_session.dart';
import '../../../models/staff_user.dart';
import '../../../services/admin_auth_service.dart';
import '../../../services/admin_order_focus_service.dart';
import '../../../services/admin_order_monitor_service.dart';
import '../../../services/offline/pos_sync_service.dart';
import '../../../services/pos_operations_service.dart';
import '../../../services/pos_security_service.dart';
import '../../../services/restaurant_settings_service.dart';
import '../../language_toggle_button.dart';
import '../admin_pos_panel.dart';
import 'pos_add_staff_dialog.dart';
import 'pos_close_shift_dialog.dart';
import 'pos_layout.dart';
import 'pos_menu_catalog.dart';
import 'pos_menu_page.dart';
import 'pos_driver_handoff_page.dart';
import 'pos_online_orders_page.dart';
import 'pos_reports_page.dart';
import 'pos_staff_empty_state.dart';
import 'pos_staff_page.dart';
import 'pos_void_orders_page.dart';
import 'pos_dine_in_page.dart';
import 'pos_in_page_overlay.dart';
import 'pos_printer_settings_dialog.dart';

class PosShiftShell extends StatefulWidget {
  const PosShiftShell({
    super.key,
    this.onOrderSubmitted,
    this.onOpenMenu,
    this.onLogout,
    this.restaurantId,
    this.initialRoute = PosRoute.home,
    this.tableManagementEnabled = false,
  });

  final VoidCallback? onOrderSubmitted;
  final VoidCallback? onOpenMenu;
  final VoidCallback? onLogout;
  final String? restaurantId;
  final PosRoute initialRoute;
  final bool tableManagementEnabled;

  @override
  State<PosShiftShell> createState() => _PosShiftShellState();
}

class _PosShiftShellState extends State<PosShiftShell> {
  final _restaurantController = TextEditingController();
  final _cashierNameController = TextEditingController();
  final _pinController = TextEditingController();
  final _openingFloatController = TextEditingController(text: '0');

  var _loading = true;
  var _openingShift = false;
  var _error = '';
  ShiftSession? _shift;
  List<StaffUser> _staff = const [];
  var _selectedRoute = PosRoute.home;
  var _tableManagementEnabled = false;
  var _homeSheet = _PosHomeSheet.none;

  @override
  void initState() {
    super.initState();
    _selectedRoute = widget.initialRoute;
    final restaurantName = AdminAuthService.instance.restaurantName;
    if (restaurantName != null && restaurantName.trim().isNotEmpty) {
      _restaurantController.text = restaurantName.trim();
    }
    _bootstrap();
    AdminOrderFocusService.instance.addListener(_onOrderFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onOrderFocusChanged());
  }

  @override
  void didUpdateWidget(covariant PosShiftShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tableManagementEnabled == widget.tableManagementEnabled) {
      return;
    }
    setState(() {
      _tableManagementEnabled = widget.tableManagementEnabled;
      if (!_tableManagementEnabled) {
        if (_selectedRoute == PosRoute.dineIn) {
          _selectedRoute = PosRoute.home;
        }
        if (_homeSheet == _PosHomeSheet.tables) {
          _homeSheet = _PosHomeSheet.none;
        }
      }
    });
  }

  @override
  void dispose() {
    AdminOrderFocusService.instance.removeListener(_onOrderFocusChanged);
    _restaurantController.dispose();
    _cashierNameController.dispose();
    _pinController.dispose();
    _openingFloatController.dispose();
    PosSecurityService.instance.dispose();
    super.dispose();
  }

  Future<void> _refreshStaff() async {
    if (AdminAuthService.instance.isCashier) return;
    try {
      _staff = await loadPosStaffUsers();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      if (AdminAuthService.instance.isCashier) {
        await PosOperationsService.instance.restoreCashierSessionIfNeeded();
      }

      final settings = await RestaurantSettingsService.instance.load();
      _tableManagementEnabled =
          widget.tableManagementEnabled || settings.tableManagementEnabled;
      PosSecurityService.instance.configure(
        autoLockMinutes: settings.posAutoLockMinutes,
        onLockChanged: () {
          if (mounted) setState(() {});
        },
      );

      if (!AdminAuthService.instance.isCashier) {
        _staff = await loadPosStaffUsers();
      }

      final cashier = PosOperationsService.instance.cashierSession;
      try {
        _shift = await PosOperationsService.instance.fetchCurrentShift(
          cashierId: cashier?.staff.id,
        );
      } catch (_) {
        _shift = await PosSyncService.instance.loadCachedShift();
      }
      if (_shift != null) {
        unawaited(PosSyncService.instance.cacheShift(_shift!));
      }
      unawaited(PosSyncService.instance.start());
      unawaited(AdminOrderMonitorService.instance.start());
    } catch (error) {
      _shift ??= await PosSyncService.instance.loadCachedShift();
      if (_shift == null) {
        _error = error.toString().replaceFirst('Exception: ', '');
      }
      unawaited(PosSyncService.instance.start());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginCashier() async {
    final s = AppStrings.read(context);
    final restaurantName = _restaurantController.text.trim();
    final cashierName = _cashierNameController.text.trim();
    final password = _pinController.text.trim();

    if (restaurantName.isEmpty) {
      setState(
        () => _error = s.tr('أدخل اسم المطعم', 'Enter the restaurant name'),
      );
      return;
    }
    if (cashierName.isEmpty) {
      setState(
        () => _error = s.tr('أدخل اسم الكاشير', 'Enter the cashier name'),
      );
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = s.tr('أدخل كلمة المرور', 'Enter the password'));
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      await PosOperationsService.instance.loginWithPin(
        password,
        cashierName: cashierName,
        restaurantName: restaurantName,
      );
      final cashier = PosOperationsService.instance.cashierSession;
      _shift = await PosOperationsService.instance.fetchCurrentShift(
        cashierId: cashier?.staff.id,
      );
      if (_shift != null) {
        unawaited(PosSyncService.instance.cacheShift(_shift!));
      }
      unawaited(PosSyncService.instance.start());
      _pinController.clear();
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openShift() async {
    final cashier = PosOperationsService.instance.cashierSession;
    if (cashier == null) return;

    setState(() => _openingShift = true);
    try {
      final openingFloat =
          double.tryParse(_openingFloatController.text.trim()) ?? 0;
      _shift = await PosOperationsService.instance.openShift(
        cashierId: cashier.staff.id,
        cashierName: cashier.staff.name,
        roleId: cashier.roleId.isNotEmpty
            ? cashier.roleId
            : cashier.staff.roleId,
        openingFloat: openingFloat,
      );
      unawaited(PosSyncService.instance.cacheShift(_shift!));
      setState(() => _selectedRoute = PosRoute.home);
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _openingShift = false);
    }
  }

  Future<void> _closeShift() async {
    if (_shift == null) return;
    final closed = await showPosCloseShiftDialog(context, shift: _shift!);
    if (closed == null || !mounted) return;
    await showShiftSummaryDialog(context, closed);
    setState(() {
      _shift = null;
      _selectedRoute = PosRoute.home;
    });
  }

  Future<void> _unlock() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) return;
    try {
      await PosOperationsService.instance.loginWithPin(pin);
      PosSecurityService.instance.unlock();
      _pinController.clear();
      setState(() {});
    } catch (error) {
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _onUserActivity() {
    PosSecurityService.instance.registerActivity();
  }

  void _onRouteSelected(PosRoute route) {
    if (route == PosRoute.dineIn && !_tableManagementEnabled) {
      return;
    }
    setState(() {
      _selectedRoute = route;
      _homeSheet = _PosHomeSheet.none;
    });
  }

  void _onOrderFocusChanged() {
    final ref = AdminOrderFocusService.instance.pendingOrderRef;
    if (ref == null || ref.isEmpty) return;
    if (_selectedRoute == PosRoute.orders) return;
    if (!mounted) return;
    if (_selectedRoute == PosRoute.home) {
      setState(() => _homeSheet = _PosHomeSheet.orders);
      return;
    }
    setState(() => _selectedRoute = PosRoute.orders);
  }

  void _openHomeSheet(_PosHomeSheet sheet) {
    if (sheet == _PosHomeSheet.tables && !_tableManagementEnabled) {
      return;
    }
    setState(() {
      _selectedRoute = PosRoute.home;
      _homeSheet = sheet;
    });
  }

  void _closeHomeSheet() {
    if (_homeSheet == _PosHomeSheet.none) return;
    setState(() => _homeSheet = _PosHomeSheet.none);
  }

  Widget _buildRouteContent() {
    if (_shift == null || !_shift!.isOpen) {
      final cashier = PosOperationsService.instance.cashierSession;
      return cashier == null
          ? _buildCashierLogin()
          : _buildOpenShiftScreen(cashier.staff.name);
    }

    final overlay = switch (_selectedRoute) {
      PosRoute.home => null,
      PosRoute.orders => PosOnlineOrdersPage(
        tableManagementEnabled: _tableManagementEnabled,
      ),
      PosRoute.handoff => const PosDriverHandoffPage(),
      PosRoute.reports => const PosReportsPage(),
      PosRoute.voidOrders => const PosVoidOrdersPage(),
      PosRoute.staff => const PosStaffPage(),
      PosRoute.menu => const PosMenuPage(),
      PosRoute.dineIn => PosDineInPage(
        restaurantId: widget.restaurantId,
        onOrderSubmitted: widget.onOrderSubmitted,
      ),
      PosRoute.shiftClose => _buildShiftClosePlaceholder(),
    };

    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: _selectedRoute != PosRoute.home,
          child: TickerMode(
            enabled: _selectedRoute == PosRoute.home,
            child: _buildPosHome(),
          ),
        ),
        if (overlay != null) overlay,
      ],
    );
  }

  Widget _buildPosHome() {
    final s = AppStrings.of(context);
    final shift = _shift!;
    final shiftLabel =
        '${s.tr('وردية', 'Shift')}: ${shift.cashierName}';
    return Stack(
      fit: StackFit.expand,
      children: [
        AdminPosPanel(
          key: const ValueKey('pos-home-panel'),
          restaurantId: widget.restaurantId,
          onOrderSubmitted: widget.onOrderSubmitted,
          onOpenMenu: widget.onOpenMenu,
          onLogout: widget.onLogout,
          onOpenTables: () => _openHomeSheet(_PosHomeSheet.tables),
          onOpenDriverHandoff: () => _openHomeSheet(_PosHomeSheet.handoff),
          onOpenOnlineOrders: () => _openHomeSheet(_PosHomeSheet.orders),
          tableManagementEnabled: _tableManagementEnabled,
          shiftLabel: shiftLabel,
        ),
        PosInPageOverlay(
          visible:
              _tableManagementEnabled && _homeSheet == _PosHomeSheet.tables,
          title: s.tr('الطاولات', 'Tables'),
          onClose: _closeHomeSheet,
          child: PosDineInPage(
            key: const ValueKey('pos-warm-tables'),
            restaurantId: widget.restaurantId,
            onOrderSubmitted: widget.onOrderSubmitted,
          ),
        ),
        PosInPageOverlay(
          visible: _homeSheet == _PosHomeSheet.handoff,
          title: s.tr('استلام من السائق', 'Driver handoff'),
          onClose: _closeHomeSheet,
          child: const PosDriverHandoffPage(
            key: ValueKey('pos-warm-handoff'),
            showPageHeader: false,
          ),
        ),
        PosInPageOverlay(
          visible: _homeSheet == _PosHomeSheet.orders,
          title: s.tr('طلبات الموقع', 'Online orders'),
          onClose: _closeHomeSheet,
          child: PosOnlineOrdersPage(
            key: const ValueKey('pos-warm-orders'),
            showPageHeader: false,
            tableManagementEnabled: _tableManagementEnabled,
          ),
        ),
      ],
    );
  }

  Widget _buildShiftClosePlaceholder() {
    final s = AppStrings.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_clock, size: 48, color: Color(0xFF6B1124)),
            const SizedBox(height: 12),
            Text(
              s.tr('إغلاق الوردية', 'Close shift'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _shift == null || !_shift!.isOpen
                  ? s.tr(
                      'لا توجد وردية مفتوحة حالياً.',
                      'There is no open shift.',
                    )
                  : s.tr(
                      'اضغط الزر أدناه لإغلاق الوردية الحالية.',
                      'Use the button below to close the current shift.',
                    ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_shift != null && _shift!.isOpen)
              FilledButton.icon(
                onPressed: _closeShift,
                icon: const Icon(Icons.lock_clock),
                label: Text(s.tr('إغلاق الوردية الآن', 'Close shift now')),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF6B1124)),
      );
    }

    if (!PosOperationsService.instance.allows(PosPermissionKeys.posAccess) &&
        !PosOperationsService.instance.allows(
          PosPermissionKeys.processOrders,
        ) &&
        !AdminAuthService.instance.isCashier) {
      return _buildPermissionDenied(
        s.tr(
          'لا تملك صلاحية الوصول لشاشة POS.',
          'You do not have permission to access POS.',
        ),
      );
    }

    final cashier = PosOperationsService.instance.cashierSession;
    if (cashier == null) {
      return _buildCashierLogin();
    }

    final content = Listener(
      onPointerDown: (_) => _onUserActivity(),
      child: Stack(
        children: [
          _buildRouteContent(),
          if (PosSecurityService.instance.isLocked &&
              _selectedRoute == PosRoute.home &&
              _shift != null &&
              _shift!.isOpen)
            _buildLockOverlay(),
        ],
      ),
    );

    return PosLayout(
      selectedRoute: _selectedRoute,
      onRouteSelected: _onRouteSelected,
      onShiftCloseRequested: _closeShift,
      onPrinterSettings: () => showPosPrinterSettingsDialog(context),
      onLogout: widget.onLogout,
      showSidebar: true,
      tableManagementEnabled: _tableManagementEnabled,
      child: content,
    );
  }

  Widget _buildCashierLogin() {
    final s = AppStrings.of(context);
    final isCashierJwt = AdminAuthService.instance.isCashier;
    final canAddStaff =
        !isCashierJwt &&
        (AdminAuthService.instance.isRestaurantAdmin ||
            AdminAuthService.instance.isSuperAdmin ||
            PosOperationsService.instance.allows(
              PosPermissionKeys.manageStaff,
            ));
    final canContinueAsAdmin =
        !isCashierJwt &&
        (AdminAuthService.instance.isRestaurantAdmin ||
            AdminAuthService.instance.isSuperAdmin);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: LanguageToggleButton(
                    foregroundColor: const Color(0xFF6B1124),
                  ),
                ),
                Text(
                  s.tr('تسجيل دخول الكاشير', 'Cashier Sign In'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  s.tr(
                    'أدخل اسم المطعم واسم الكاشير وكلمة المرور لبدء جلسة POS',
                    'Enter the restaurant, cashier name, and password to start POS.',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (!isCashierJwt && _staff.isEmpty) ...[
                  PosStaffEmptyState(onStaffAdded: _refreshStaff),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _restaurantController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: s.tr('اسم المطعم', 'Restaurant name'),
                    hintText: s.tr(
                      'مثال: Molton Cookies أو molton-cookies',
                      'Example: Molton Cookies or molton-cookies',
                    ),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.storefront_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _cashierNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: s.tr('اسم الكاشير', 'Cashier name'),
                    hintText: s.tr('مثال: أحمد', 'Example: Ahmed'),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: InputDecoration(
                    labelText: s.tr('كلمة المرور', 'Password'),
                    hintText: s.tr('رمز PIN الخاص بالكاشير', 'Cashier PIN'),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    errorText: _error.isEmpty ? null : _error,
                  ),
                  onSubmitted: (_) => _loginCashier(),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loading ? null : _loginCashier,
                  child: Text(s.tr('دخول', 'Sign in')),
                ),
                if (canAddStaff) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await showPosAddStaffDialog(context);
                      await _refreshStaff();
                    },
                    icon: const Icon(Icons.person_add),
                    label: Text(
                      s.tr('إضافة موظف / كاشير جديد', 'Add staff / cashier'),
                    ),
                  ),
                ],
                if (canContinueAsAdmin) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () async {
                      await PosOperationsService.instance
                          .bootstrapAdminCashier();
                      setState(() {});
                    },
                    child: Text(
                      s.tr(
                        'متابعة كمدير (بدون كاشير)',
                        'Continue as manager (without cashier)',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOpenShiftScreen(String cashierName) {
    final s = AppStrings.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${s.tr('فتح وردية', 'Open shift')} — $cashierName',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _openingFloatController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: s.tr(
                      'رصيد افتتاح الدرج (د.ك)',
                      'Opening cash drawer balance (KWD)',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_error, style: TextStyle(color: Colors.red.shade700)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _openingShift ? null : _openShift,
                  child: _openingShift
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(s.tr('فتح الوردية', 'Open shift')),
                ),
                if (widget.onLogout != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: widget.onLogout,
                    icon: const Icon(Icons.logout),
                    label: Text(s.tr('تسجيل الخروج', 'Log out')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLockOverlay() {
    final s = AppStrings.of(context);
    return Container(
      color: Colors.black.withValues(alpha: 0.82),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 48,
                  color: Color(0xFF6B1124),
                ),
                const SizedBox(height: 12),
                Text(
                  s.tr('الشاشة مقفلة', 'Screen locked'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  s.tr('أدخل رمز PIN للمتابعة', 'Enter PIN to continue'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: s.tr('رمز PIN', 'PIN'),
                    border: const OutlineInputBorder(),
                    errorText: _error.isEmpty ? null : _error,
                  ),
                  onSubmitted: (_) => _unlock(),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _unlock,
                  child: Text(s.tr('فتح القفل', 'Unlock')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionDenied(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 56, color: Colors.grey.shade500),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PosHomeSheet { none, tables, handoff, orders }

PosRoute readPosRouteFromLocation() {
  if (!kIsWeb) return PosRoute.home;
  final path = Uri.base.path.replaceAll(RegExp(r'/+$'), '');
  return PosRoute.fromPath(path.isEmpty ? '/admin/pos' : path);
}
