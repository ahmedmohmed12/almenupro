import 'package:flutter/material.dart';

class DriverBrand {
  static const maroon = Color(0xFF6B1124);
  static const gold = Color(0xFFE19B0F);
  static const orange = Color(0xFFFF6A00);
  static const orangeDeep = Color(0xFFE85D00);
  static const canvas = Color(0xFFFFF7F0);
  static const ink = Color(0xFF1B1B1B);
  static const muted = Color(0xFF6B7280);
  static const card = Colors.white;

  static ThemeData theme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: orange,
        primary: orange,
        secondary: maroon,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: canvas,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: orange,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: orange.withValues(alpha: 0.16),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 11,
            color: selected ? orange : muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? orange : muted);
        }),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: orange,
        unselectedItemColor: muted,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
      ),
    );
  }
}

class MenuProLogo extends StatelessWidget {
  const MenuProLogo({super.key, this.height = 88});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/app_icon.png',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Icon(
        Icons.storefront_rounded,
        size: height * 0.7,
        color: DriverBrand.maroon,
      ),
    );
  }
}
