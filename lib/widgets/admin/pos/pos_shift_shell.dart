import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/pos_role.dart';
import '../../../models/shift_session.dart';
import '../../../models/staff_user.dart';
import '../../../utils/admin_route_nav.dart';
import '../../../services/admin_auth_service.dart';
import '../../../services/admin_order_monitor_service.dart';
import '../../../services/pos_operations_service.dart';
import '../../../services/pos_security_service.dart';
import '../../../services/restaurant_settings_service.dart';
import '../admin_pos_panel.dart';
import 'pos_add_staff_dialog.dart';
import 'pos_close_shift_dialog.dart';
import 'pos_layout.dart';
import 'pos_menu_catalog.dart';
import 'pos_menu_page.dart';
import 'pos_online_orders_alert.dart';
import 'pos_online_orders_page.dart';
import 'pos_reports_page.dart';
import 'pos_staff_empty_state.dart';
import 'pos_staff_page.dart';
import 'pos_void_orders_page.dart';
import 'pos_dine_in_page.dart';

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
  late PosRoute _selectedRoute;
  var _tableManagementEnabled = false;

  @override
  void initState() {
    super.initState();
    _selectedRoute = widget.initialRoute;
    final restaurantName = AdminAuthService.instance.restaurantName;
    if (restaurantName != null && restaurantName.trim().isNotEmpty) {
      _restaurantController.text = restaurantName.trim();
    }
    _bootstrap();
  }

  @override
  void dispose() {
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
      _shift = await PosOperationsService.instance.fetchCurrentShift(
        cashierId: cashier?.staff.id,
      );
      unawaited(AdminOrderMonitorService.instance.start());
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginCashier() async {
    final restaurantName = _restaurantController.text.trim();
    final cashierName = _cashierNameController.text.trim();
    final password = _pinController.text.trim();

    if (restaurantName.isEmpty) {
      setState(() => _error = 'أدخل اسم المطعم');
      return;
    }
    if (cashierName.isEmpty) {
      setState(() => _error = 'أدخل اسم الكاشير');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'أدخل كلمة المرور');
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
      final openingFloat = double.tryParse(_openingFloatController.text.trim()) ?? 0;
      _shift = await PosOperationsService.instance.openShift(
        cashierId: cashier.staff.id,
        cashierName: cashier.staff.name,
        roleId: cashier.roleId.isNotEmpty ? cashier.roleId : cashier.staff.roleId,
        openingFloat: openingFloat,
      );
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
    setState(() => _selectedRoute = route);
  }

  void _openOnlineOrders() {
    setState(() => _selectedRoute = PosRoute.orders);
    navigateToAdminPath(PosRoute.orders.path);
  }

  Widget _buildRouteContent() {
    switch (_selectedRoute) {
      case PosRoute.home:
        if (_shift == null || !_shift!.isOpen) {
          final cashier = PosOperationsService.instance.cashierSession;
          return cashier == null
              ? _buildCashierLogin()
              : _buildOpenShiftScreen(cashier.staff.name);
        }
        final canReceiveOnline = PosOperationsService.instance.allows(
          PosPermissionKeys.receiveOnlineOrders,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildShiftBanner(),
            if (canReceiveOnline)
              ValueListenableBuilder<int>(
                valueListenable: AdminOrderMonitorService.instance.pendingCount,
                builder: (context, count, _) => PosOnlineOrdersAlertBar(
                  pendingCount: count,
                  onOpen: _openOnlineOrders,
                ),
              ),
            Expanded(
              child: AdminPosPanel(
                restaurantId: widget.restaurantId,
                onOrderSubmitted: widget.onOrderSubmitted,
                onOpenMenu: widget.onOpenMenu,
                onLogout: widget.onLogout,
              ),
            ),
          ],
        );
      case PosRoute.orders:
        return const PosOnlineOrdersPage();
      case PosRoute.reports:
        return const PosReportsPage();
      case PosRoute.voidOrders:
        return const PosVoidOrdersPage();
      case PosRoute.staff:
        return const PosStaffPage();
      case PosRoute.menu:
        return const PosMenuPage();
      case PosRoute.dineIn:
        return PosDineInPage(
          restaurantId: widget.restaurantId,
          onOrderSubmitted: widget.onOrderSubmitted,
        );
      case PosRoute.shiftClose:
        return _buildShiftClosePlaceholder();
    }
  }

  Widget _buildShiftClosePlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_clock, size: 48, color: Color(0xFF6B1124)),
            const SizedBox(height: 12),
            const Text(
              'إغلاق الوردية',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _shift == null || !_shift!.isOpen
                  ? 'لا توجد وردية مفتوحة حالياً.'
                  : 'اضغط الزر أدناه لإغلاق الوردية الحالية.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_shift != null && _shift!.isOpen)
              FilledButton.icon(
                onPressed: _closeShift,
                icon: const Icon(Icons.lock_clock),
                label: const Text('إغلاق الوردية الآن'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF6B1124)));
    }

    if (!PosOperationsService.instance.allows(PosPermissionKeys.posAccess) &&
        !PosOperationsService.instance.allows(PosPermissionKeys.processOrders) &&
        !AdminAuthService.instance.isCashier) {
      return _buildPermissionDenied(
        'لا تملك صلاحية الوصول لشاشة POS.',
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
      showSidebar: true,
      tableManagementEnabled: _tableManagementEnabled,
      child: content,
    );
  }

  Widget _buildShiftBanner() {
    final shift = _shift!;
    return Material(
      color: const Color(0xFF6B1124),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.schedule, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'وردية مفتوحة — ${shift.cashierName} • من ${shift.openedAt.toLocal().toString().substring(0, 16)}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCashierLogin() {
    final isCashierJwt = AdminAuthService.instance.isCashier;
    final canAddStaff = !isCashierJwt &&
        (AdminAuthService.instance.isRestaurantAdmin ||
            AdminAuthService.instance.isSuperAdmin ||
            PosOperationsService.instance.allows(PosPermissionKeys.manageStaff));
    final canContinueAsAdmin = !isCashierJwt &&
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
                const Text(
                  'تسجيل دخول الكاشير',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'أدخل اسم المطعم واسم الكاشير وكلمة المرور لبدء جلسة POS',
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
                  decoration: const InputDecoration(
                    labelText: 'اسم المطعم',
                    hintText: 'مثال: Molton Cookies أو molton-cookies',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _cashierNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'اسم الكاشير',
                    hintText: 'مثال: أحمد',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور',
                    hintText: 'رمز PIN الخاص بالكاشير',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    errorText: _error.isEmpty ? null : _error,
                  ),
                  onSubmitted: (_) => _loginCashier(),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loading ? null : _loginCashier,
                  child: const Text('دخول'),
                ),
                if (canAddStaff) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await showPosAddStaffDialog(context);
                      await _refreshStaff();
                    },
                    icon: const Icon(Icons.person_add),
                    label: const Text('إضافة موظف / كاشير جديد'),
                  ),
                ],
                if (canContinueAsAdmin) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () async {
                      await PosOperationsService.instance.bootstrapAdminCashier();
                      setState(() {});
                    },
                    child: const Text('متابعة كمدير (بدون كاشير)'),
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
                  'فتح وردية — $cashierName',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _openingFloatController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'رصيد افتتاح الدرج (د.ك)',
                    border: OutlineInputBorder(),
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
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('فتح الوردية'),
                ),
                if (widget.onLogout != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: widget.onLogout,
                    icon: const Icon(Icons.logout),
                    label: const Text('تسجيل الخروج'),
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
                const Icon(Icons.lock_outline, size: 48, color: Color(0xFF6B1124)),
                const SizedBox(height: 12),
                const Text(
                  'الشاشة مقفلة',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'أدخل رمز PIN للمتابعة',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'رمز PIN',
                    border: const OutlineInputBorder(),
                    errorText: _error.isEmpty ? null : _error,
                  ),
                  onSubmitted: (_) => _unlock(),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _unlock, child: const Text('فتح القفل')),
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

PosRoute readPosRouteFromLocation() {
  if (!kIsWeb) return PosRoute.home;
  final path = Uri.base.path.replaceAll(RegExp(r'/+$'), '');
  return PosRoute.fromPath(path.isEmpty ? '/admin/pos' : path);
}
