import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/delivery_dispatch.dart';
import '../l10n/app_strings.dart';
import '../providers/locale_provider.dart';
import '../services/admin_auth_service.dart';
import '../services/api_service.dart';
import '../services/driver_firestore_sync.dart';
import '../widgets/admin/driver_station_screen.dart';
import '../widgets/language_toggle_button.dart';
import 'driver_brand.dart';
import 'driver_mobile.dart';
import 'menu_pro_mark.dart';

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();
    return MaterialApp(
      title: locale.isArabic ? 'سائق المنيو برو' : 'AlMenuPro Driver',
      debugShowCheckedModeBanner: false,
      locale: Locale(locale.localeCode),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: DriverBrand.theme(),
      builder: (context, child) {
        return Directionality(
          textDirection: locale.textDirection,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const DriverRoot(),
    );
  }
}

class DriverRoot extends StatefulWidget {
  const DriverRoot({super.key});

  @override
  State<DriverRoot> createState() => _DriverRootState();
}

class _DriverRootState extends State<DriverRoot> {
  var _ready = false;
  var _drawComplete = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await AdminAuthService.instance.initialize();
    await initDriverMobileServices();
    if (AdminAuthService.instance.isDriver) {
      await _registerPush();
    }
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _registerPush() async {
    try {
      final inbox = await ApiService.instance.fetchDriverInbox();
      final driverRaw = inbox['driver'];
      if (driverRaw is! Map) return;
      final driver = DeliveryDriver.fromJson(
        Map<String, dynamic>.from(driverRaw),
      );
      await registerDriverFcmToken(driver.id);
      await syncDriverProfileToFirestore(driver);
    } catch (_) {}
  }

  Future<void> _logout() async {
    await stopDriverLocationTracking();
    await AdminAuthService.instance.logout();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || !_drawComplete) {
      return DriverBrandedSplash(
        loading: !_ready,
        onDrawComplete: () {
          if (mounted) setState(() => _drawComplete = true);
        },
      );
    }
    if (AdminAuthService.instance.isDriver) {
      return DriverStationScreen(onLogout: () => unawaited(_logout()));
    }
    return DriverLoginScreen(
      onLoggedIn: () async {
        await initDriverMobileServices();
        await _registerPush();
        if (mounted) setState(() {});
      },
    );
  }
}

class DriverLoginScreen extends StatefulWidget {
  const DriverLoginScreen({super.key, required this.onLoggedIn});

  final Future<void> Function() onLoggedIn;

  @override
  State<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends State<DriverLoginScreen> {
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final strings = AppStrings.read(context);
    final phone = _phone.text.trim();
    final pin = _pin.text.trim();
    if (phone.length < 2) {
      setState(
        () => _error = strings.tr(
          'أدخل رقم الهاتف المسجّل في لوحة الأدمن',
          'Enter the phone number registered by the admin',
        ),
      );
      return;
    }
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      setState(
        () => _error = strings.tr(
          'رمز الدخول PIN يجب أن يكون 4 أرقام',
          'The login PIN must be 4 digits',
        ),
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await AdminAuthService.instance.loginDriver(
        phone: phone,
        pin: pin,
      );
      if (!session.isDriver) {
        await AdminAuthService.instance.logout();
        throw Exception(
          strings.tr(
            'هذا الحساب ليس حساب سائق',
            'This account is not a driver account',
          ),
        );
      }
      await widget.onLoggedIn();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      backgroundColor: DriverBrand.canvas,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 56, 24, 36),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [DriverBrand.orange, DriverBrand.orangeDeep],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: Stack(
              children: [
                const PositionedDirectional(
                  top: 0,
                  end: 0,
                  child: LanguageToggleButton(
                    compact: true,
                    foregroundColor: Colors.white,
                  ),
                ),
                Column(
                  children: [
                    const MenuProLogo(height: 92),
                    const SizedBox(height: 12),
                    Text(
                      strings.tr('سائق المنيو برو', 'AlMenuPro Driver'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      strings.tr(
                        'ادخل برقم هاتفك ورمز PIN من الأدمن',
                        'Sign in with your phone number and admin-issued PIN',
                      ),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Material(
                      color: Colors.white,
                      elevation: 2,
                      shadowColor: Colors.black12,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            TextField(
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: strings.tr(
                                  'رقم الهاتف أو الاسم',
                                  'Phone number or name',
                                ),
                                prefixIcon: const Icon(Icons.phone_android),
                                filled: true,
                                fillColor: const Color(0xFFF7F7F7),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _pin,
                              obscureText: true,
                              maxLength: 4,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                labelText: strings.tr(
                                  'رمز الدخول PIN',
                                  'Login PIN',
                                ),
                                prefixIcon: const Icon(Icons.lock_outline),
                                filled: true,
                                fillColor: const Color(0xFFF7F7F7),
                                counterText: '',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onSubmitted: (_) {
                                if (!_busy) _login();
                              },
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xFFC62828),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: DriverBrand.orange,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed: _busy ? null : _login,
                                child: _busy
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        strings.tr('دخول', 'Sign in'),
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      strings.tr(
                        'المناطق يحددها الأدمن من «مناطق التوصيل». لن تصلك طلبات خارج مناطقك المفعّلة.',
                        'The admin manages your delivery areas. You will not receive orders outside your active areas.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF6B6B6B),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
