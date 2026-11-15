import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_auth_service.dart';
import '../../services/pos_operations_service.dart';
import '../../utils/admin_deep_link.dart';
import '../../utils/admin_route_nav.dart';
import '../../widgets/auth/admin_login_shell.dart';
import '../../widgets/auth/admin_login_theme.dart';
import 'admin_login_success.dart';

class PosLoginScreen extends StatefulWidget {
  const PosLoginScreen({super.key, this.redirect});

  final String? redirect;

  @override
  State<PosLoginScreen> createState() => _PosLoginScreenState();
}

class _PosLoginScreenState extends State<PosLoginScreen> {
  final _restaurantController = TextEditingController();
  final _cashierController = TextEditingController();
  final _passwordController = TextEditingController();
  var _submitting = false;
  String? _error;

  Uri get _uri => kIsWeb ? Uri.base : Uri(path: AdminDeepLink.posLoginPath);

  String? get _redirect =>
      widget.redirect ??
      AdminDeepLink.parseRedirect(_uri) ??
      AdminDeepLink.sanitizeRedirect(readStoredAdminRedirect());

  @override
  void initState() {
    super.initState();
    final redirect = _redirect;
    if (redirect != null) storeAdminRedirect(redirect);
  }

  @override
  void dispose() {
    _restaurantController.dispose();
    _cashierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await AdminAuthService.instance.loginCashier(
        restaurantName: _restaurantController.text.trim(),
        cashierName: _cashierController.text.trim(),
        password: _passwordController.text,
      );
      if (!result.session.isKitchen) {
        PosOperationsService.instance.applyCashierSession(result.cashierSession);
      }
      if (!mounted) return;
      clearStoredAdminRedirect();
      completeAdminLoginNavigation(context, redirect: _redirect);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return AdminLoginShell(
      icon: Icons.point_of_sale,
      title: s.tr('دخول نقطة البيع', 'POS Sign In'),
      subtitle: s.tr(
        'كاشير · مطبخ · سائق',
        'Cashier · Kitchen · Driver',
      ),
      footer: TextButton(
        onPressed: () => Navigator.of(context).pushReplacementNamed(
          AdminDeepLink.managerLoginPath,
        ),
        child: Text(s.tr('دخول المدير', 'Manager login')),
      ),
      children: [
        TextField(
          controller: _restaurantController,
          textInputAction: TextInputAction.next,
          decoration: AdminLoginTheme.fieldDecoration(
            label: s.tr('اسم المطعم', 'Restaurant name'),
            hint: s.tr('اسم المطعم أو المعرف', 'Restaurant name or slug'),
            trailingIcon: const Icon(Icons.store_outlined, color: AdminLoginTheme.burgundy),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _cashierController,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
          decoration: AdminLoginTheme.fieldDecoration(
            label: s.tr('اسم المستخدم', 'Username'),
            hint: s.tr(
              'اسم الكاشير أو مستخدم المطبخ',
              'Cashier or kitchen username',
            ),
            leadingIcon: const Icon(Icons.badge_outlined, color: AdminLoginTheme.burgundy),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: true,
          onSubmitted: (_) => _submit(),
          decoration: AdminLoginTheme.fieldDecoration(
            label: s.tr('كلمة المرور / PIN', 'Password / PIN'),
            error: _error,
            leadingIcon: const Icon(Icons.pin_outlined, color: AdminLoginTheme.burgundy),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: AdminLoginTheme.primaryButton(disabled: _submitting),
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(s.tr('دخول', 'Sign In')),
          ),
        ),
      ],
    );
  }
}