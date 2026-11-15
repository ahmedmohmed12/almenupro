import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/locale_provider.dart';
import 'screens/admin_dashboard.dart';
import 'services/menu_storage_service.dart';
import 'theme/app_theme.dart';
import 'utils/firebase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isFirebaseConfigured) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } else {
    debugPrint(
      'Skipping Firebase init: replace YOUR_* values in lib/firebase_options.dart.',
    );
  }
  try {
    await MenuStorageService.instance.initialize();
  } catch (_) {}
  runApp(
    ChangeNotifierProvider(
      create: (_) => LocaleProvider()..load(),
      child: const AdminApp(),
    ),
  );
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();
    return MaterialApp(
      title: locale.isArabic ? 'المنيو برو' : 'AlMenuPro',
      debugShowCheckedModeBanner: false,
      locale: Locale(locale.localeCode),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light().copyWith(
        textTheme: GoogleFonts.cairoTextTheme(AppTheme.light().textTheme),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: locale.textDirection,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const AdminDashboard(),
    );
  }
}
