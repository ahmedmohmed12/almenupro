import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/cart_provider.dart';
import 'providers/customer_session_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/order_type_provider.dart';
import 'screens/admin_dashboard.dart';
import 'screens/auth/manager_login_screen.dart';
import 'screens/auth/pos_login_screen.dart';
import 'screens/auth/super_admin_login_screen.dart';
import 'utils/auth_login_routes.dart';
import 'screens/client_menu_page.dart';
import 'screens/order_rating_screen.dart';
import 'screens/restaurant_link_hub_screen.dart';
import 'screens/table_qr_ordering_screen.dart';
import 'screens/table_qr_portal_screen.dart';
import 'screens/menu_screen.dart';
import 'driver/driver_app.dart';
import 'screens/restaurant_directory_screen.dart';
import 'services/menu_storage_service.dart';
import 'services/molton_upload_service.dart';
import 'services/seed_service.dart';
import 'theme/app_theme.dart';
import 'utils/configure_url_strategy.dart';
import 'utils/firebase_config.dart';
import 'utils/restaurant_route.dart';
import 'utils/table_qr_route.dart';
import 'widgets/app_error_boundary.dart';

Future<void> main() async {
  configureUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (details) => AppErrorBoundary.releaseFallback(details);

  try {
    if (isFirebaseConfigured) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else {
      debugPrint(
        'Skipping Firebase init: replace YOUR_* values in lib/firebase_options.dart.',
      );
    }
    await MenuStorageService.instance.initialize();
    if (isFirebaseConfigured) {
      unawaited(SeedService().seedMenuIfEmpty());
      unawaited(MoltonUploadService().uploadMoltonDataIfEmpty());
    }
  } catch (e) {
    debugPrint('Bootstrap error: $e');
    try {
      await MenuStorageService.instance.initialize();
    } catch (_) {}
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static String normalizeRoute(String? routeName) {
    var route = (routeName == null || routeName.isEmpty)
        ? (kIsWeb ? Uri.base.path : '/')
        : routeName;
    if (route.endsWith('/') && route.length > 1) {
      route = route.substring(0, route.length - 1);
    }
    return route.isEmpty ? '/' : route;
  }

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final path = normalizeRoute(settings.name);
    final uri = Uri.tryParse(settings.name ?? path) ?? Uri(path: path);
    final query = <String, String>{
      if (kIsWeb) ...Uri.base.queryParameters,
      ...uri.queryParameters,
    };

    if (path == AuthLoginRoutes.legacyLogin ||
        path == AuthLoginRoutes.manager) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const ManagerLoginScreen(),
      );
    }
    if (path == AuthLoginRoutes.superAdmin) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const SuperAdminLoginScreen(),
      );
    }
    if (AuthLoginRoutes.posPaths.contains(path)) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const PosLoginScreen(),
      );
    }
    if (path == '/admin' || path.startsWith('/admin/')) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const AdminDashboard(),
      );
    }

    final linkHubSlug = RestaurantRoute.parseLinkHubSlug(path) ??
        (kIsWeb ? RestaurantRoute.parseLinkHubSlug(Uri.base.path) : null);
    if (linkHubSlug != null) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => RestaurantLinkHubScreen(slug: linkHubSlug),
      );
    }

    final orderRate = RegExp(r'^/order/([^/]+)/rate$').firstMatch(path);
    if (orderRate != null) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => OrderRatingScreen(
          orderId: Uri.decodeComponent(orderRate.group(1)!),
          token: query['token'] ?? '',
        ),
      );
    }

    final tableQrOrder = RegExp(
      r'^/table/([^/]+)/([^/]+)/order$',
    ).firstMatch(path);
    if (tableQrOrder != null) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => TableQrOrderingScreen(
          branchId: Uri.decodeComponent(tableQrOrder.group(1)!),
          tableId: Uri.decodeComponent(tableQrOrder.group(2)!),
          restaurantId: query['rest'] ?? query['restaurant_id'],
        ),
      );
    }

    final tableQr = RegExp(r'^/table/([^/]+)/([^/]+)$').firstMatch(path);
    if (tableQr != null) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => TableQrPortalScreen(
          branchId: Uri.decodeComponent(tableQr.group(1)!),
          tableId: Uri.decodeComponent(tableQr.group(2)!),
        ),
      );
    }

    final tableQuery = TableQrRouteParams.fromUri(
      Uri(path: path, queryParameters: query),
    );
    if (tableQuery != null &&
        tableQuery.tableId.isNotEmpty &&
        (path == '/menu' || path.endsWith('/menu'))) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => TableQrOrderingScreen(
          branchId: tableQuery.branchId.isNotEmpty
              ? tableQuery.branchId
              : tableQuery.restaurantId,
          tableId: tableQuery.tableId,
          restaurantId: tableQuery.restaurantId,
          restaurantSlug: tableQuery.slug,
        ),
      );
    }

    switch (path) {
      case '/driver':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const DriverRoot(),
        );
      case '/legacy-menu':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const ClientMenuPage(),
        );
      case '/restaurants':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const RestaurantDirectoryScreen(),
        );
    }

    if (AuthLoginRoutes.isStaffPath(path)) {
      if (AuthLoginRoutes.isAdminShellPath(path)) {
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const AdminDashboard(),
        );
      }
      if (path == AuthLoginRoutes.superAdmin) {
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const SuperAdminLoginScreen(),
        );
      }
      if (AuthLoginRoutes.posPaths.contains(path)) {
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const PosLoginScreen(),
        );
      }
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const ManagerLoginScreen(),
      );
    }

    final slug =
        RestaurantRoute.parseSlug(path, query: query) ??
        RestaurantRoute.slugFromBrowserLocation();
    if (slug == null || slug.isEmpty) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const RestaurantDirectoryScreen(),
      );
    }
    return MaterialPageRoute(
      settings: settings,
      builder: (_) => MenuScreen(
        slug: slug,
        dineInTableId:
            query['table'] ?? query['table_id'] ?? query['tableId'],
        dineInTableName:
            query['table_name'] ?? query['tableName'],
      ),
    );
  }

  static List<Route<dynamic>> onGenerateInitialRoutes(String initialRoute) {
    final fromBrowser = kIsWeb ? Uri.base.path : '';
    final route = normalizeRoute(
      fromBrowser.isNotEmpty && fromBrowser != '/'
          ? fromBrowser
          : (initialRoute.isNotEmpty ? initialRoute : fromBrowser),
    );
    return [onGenerateRoute(RouteSettings(name: route))];
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()..load()),
        ChangeNotifierProvider(create: (_) => OrderTypeProvider()),
        ChangeNotifierProvider(create: (_) => CustomerSessionProvider()),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, locale, _) => MaterialApp(
          title: 'Almenupro',
          debugShowCheckedModeBanner: false,
          locale: Locale(locale.localeCode),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.light(),
          onGenerateRoute: onGenerateRoute,
          onUnknownRoute: onGenerateRoute,
          onGenerateInitialRoutes: onGenerateInitialRoutes,
          builder: (context, child) {
            if (child == null) {
              return const ColoredBox(
                color: AppTheme.brandBackground,
                child: Center(
                  child: CircularProgressIndicator(color: AppTheme.brandOrange),
                ),
              );
            }
            return Directionality(
              textDirection: locale.textDirection,
              child: child,
            );
          },
        ),
      ),
    );
  }
}
