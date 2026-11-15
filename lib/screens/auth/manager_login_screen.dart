import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/restaurant.dart';
import '../../services/admin_auth_service.dart';
import '../../utils/admin_deep_link.dart';
import '../../utils/admin_route_nav.dart';
import '../../widgets/auth/admin_login_shell.dart';
import '../../widgets/auth/admin_login_theme.dart';
import '../../widgets/auth/restaurant_slug_search_field.dart';
import 'admin_login_success.dart';

class ManagerLoginScreen extends StatefulWidget {
  const ManagerLoginScreen({
    super.key,
    this.redirect,
    this.onAuthenticated,
  });

  final String? redirect;
  final Future<void> Function()? onAuthenticated;

  @override
  State<ManagerLoginScreen> createState() => _ManagerLoginScreenState();
}

class _ManagerLoginScreenState extends State<ManagerLoginScreen> {
  final _slugController = TextEditingController();
  final _passwordController = TextEditingController();
  final _slugFocus = FocusNode();
  var _submitting = false;
  String? _error;
  Restaurant? _selected;

  Uri get _uri => kIsWeb ? Uri.base : Uri(path: AdminDeepLink.managerLoginPath);

  String? get _redirect =>
      widget.redirect ??
      AdminDeepLink.parseRedirect(_uri) ??
      AdminDeepLink.sanitizeRedirect(readStoredAdminRedirect());

  @override
  void initState() {
    super.initState();
    final redirect = _redirect;
    if (redirect != null) {
      storeAdminRedirect(redirect);
    }
  }

  @override
  void dispose() {
    _slugController.dispose();
    _passwordController.dispose();
    _slugFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final slug = _slugController.text.trim();
    if (slug.isEmpty) {
      setState(() => _error = 'يرجى اختيار أو كتابة معرف المطعم');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await AdminAuthService.instance.loginRestaurantAdmin(
        restaurantSlug: slug,
        password: _passwordController.text,
      );
      if (!mounted) return;
      clearStoredAdminRedirect();
      final embedded = widget.onAuthenticated;
      if (embedded != null) {
        await embedded();
        return;
      }
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
      icon: Icons.storefront_rounded,
      title: s.tr('دخول مدير المطعم', 'Restaurant Manager Sign In'),
      subtitle: s.tr(
        'لوحة المتابعة والإعدادات',
        'Dashboard and restaurant settings',
      ),
      footer: _linkRow(s),
      children: [
        RestaurantSlugSearchField(
          controller: _slugController,
          focusNode: _slugFocus,
          errorText: _error != null && _slugController.text.isEmpty ? _error : null,
          onSelected: (restaurant) => setState(() => _selected = restaurant),
        ),
        if (_selected != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              _selected!.name,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: true,
          onSubmitted: (_) => _submit(),
          decoration: AdminLoginTheme.fieldDecoration(
            label: s.tr('كلمة المرور', 'Password'),
            error: _error != null && _slugController.text.isNotEmpty ? _error : null,
            leadingIcon: const Icon(Icons.lock_outline, color: AdminLoginTheme.burgundy),
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
                : Text(s.tr('دخول لوحة المطعم', 'Restaurant Dashboard Sign In')),
          ),
        ),
      ],
    );
  }

  Widget _linkRow(AppStrings s) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 6,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pushReplacementNamed(
            AdminDeepLink.posLoginPath,
          ),
          child: Text(s.tr('دخول الكاشير / المطبخ', 'Cashier / Kitchen')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pushReplacementNamed(
            AdminDeepLink.superAdminLoginPath,
          ),
          child: const Text('Super Admin'),
        ),
      ],
    );
  }
}