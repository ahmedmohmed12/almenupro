import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/pos_role.dart';
import '../../../models/staff_user.dart';
import '../../../services/pos_operations_service.dart';
import 'pos_add_staff_dialog.dart';
import 'pos_staff_empty_state.dart';

/// PIN login + add-cashier entry used in admin staff tab and POS shell.
class PosCashierLoginPanel extends StatefulWidget {
  const PosCashierLoginPanel({
    super.key,
    this.onLoggedIn,
    this.compact = false,
  });

  final VoidCallback? onLoggedIn;
  final bool compact;

  @override
  State<PosCashierLoginPanel> createState() => _PosCashierLoginPanelState();
}

class _PosCashierLoginPanelState extends State<PosCashierLoginPanel> {
  final _pinController = TextEditingController();
  var _loading = true;
  var _submitting = false;
  var _error = '';
  List<StaffUser> _staff = const [];

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      _staff = await loadPosStaffUsers();
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _login() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) return;
    setState(() {
      _submitting = true;
      _error = '';
    });
    try {
      await PosOperationsService.instance.loginWithPin(pin);
      _pinController.clear();
      widget.onLoggedIn?.call();
      if (mounted) setState(() {});
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _continueAsAdmin() async {
    await PosOperationsService.instance.bootstrapAdminCashier();
    widget.onLoggedIn?.call();
    if (mounted) setState(() {});
  }

  Future<void> _logoutCashier() async {
    PosOperationsService.instance.clearCashierSession();
    widget.onLoggedIn?.call();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = PosOperationsService.instance.cashierSession;
    final card = Card(
      margin: widget.compact ? EdgeInsets.zero : const EdgeInsets.all(24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: Color(0xFF6B1124)),
                ),
              )
            : session != null
                ? _buildActiveSession(session.staff.name)
                : _buildLoginForm(),
      ),
    );

    if (widget.compact) return card;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: card,
      ),
    );
  }

  Widget _buildActiveSession(String name) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'تسجيل دخول الكاشير',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'الجلسة الحالية: $name',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _logoutCashier,
          icon: const Icon(Icons.logout),
          label: const Text('تسجيل خروج الكاشير'),
        ),
      ],
    );
  }

  Widget _buildLoginForm() {
    final canManageStaff =
        PosOperationsService.instance.allows(PosPermissionKeys.manageStaff) ||
            PosOperationsService.instance.allows(PosPermissionKeys.posAccess);

    return Column(
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
          'أدخل رمز PIN الخاص بالموظف أو الكاشير لبدء الجلسة',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        if (_staff.isEmpty) ...[
          PosStaffEmptyState(onStaffAdded: _loadStaff),
          const SizedBox(height: 16),
        ],
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
          onSubmitted: (_) => _login(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _submitting ? null : _login,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('دخول'),
        ),
        if (_staff.isNotEmpty && canManageStaff) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await showPosAddStaffDialog(context);
              await _loadStaff();
            },
            icon: const Icon(Icons.person_add),
            label: const Text('إضافة موظف / كاشير جديد'),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: _continueAsAdmin,
          child: const Text('متابعة كمدير (بدون PIN)'),
        ),
      ],
    );
  }
}
