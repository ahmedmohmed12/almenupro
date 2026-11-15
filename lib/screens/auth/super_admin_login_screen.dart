import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_auth_service.dart';
import '../../utils/admin_deep_link.dart';
import '../../utils/admin_route_nav.dart';
import '../../widgets/auth/admin_login_shell.dart';
import '../../widgets/auth/admin_login_theme.dart';
import 'admin_login_success.dart';

class SuperAdminLoginScreen extends StatefulWidget {
  const SuperAdminLoginScreen({super.key, this.redirect});

  final String? redirect;

  @override
  State<SuperAdminLoginScreen> createState() => _SuperAdminLoginScreenState();
}

class _SuperAdminLoginScreenState extends State<SuperAdminLoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  var _submitting = false;
  String? _error;

  Uri get _uri => kIsWeb ? Uri.base : Uri(path: AdminDeepLink.superAdminLoginPath);

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
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await AdminAuthService.instance.loginSuperAdmin(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
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
      icon: Icons.shield_outlined,
      title: 'AlMenuPro',
      subtitle: s.tr('دخول Super Admin', 'Super Admin Sign In'),
      footer: TextButton(
        onPressed: () => Navigator.of(context).pushReplacementNamed(
          AdminDeepLink.managerLoginPath,
        ),
        child: Text(s.tr('دخول مدير المطعم', 'Restaurant manager login')),
      ),
      children: [
        TextField(
          controller: _usernameController,
          textInputAction: TextInputAction.next,
          decoration: AdminLoginTheme.fieldDecoration(
            label: s.tr('اسم المستخدم', 'Username'),
            leadingIcon: const Icon(Icons.person_outline, color: AdminLoginTheme.burgundy),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: true,
          onSubmitted: (_) => _submit(),
          decoration: AdminLoginTheme.fieldDecoration(
            label: s.tr('كلمة المرور', 'Password'),
            error: _error,
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
                : Text(s.tr('دخول Super Admin', 'Super Admin Sign In')),
          ),
        ),
      ],
    );
  }
}