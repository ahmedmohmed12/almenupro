import 'package:flutter/material.dart';

/// Foodics-inspired visual tokens for the POS cashier experience.
abstract final class PosTheme {
  static const bg = Color(0xFFF8F9FA);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF8F9FA);
  static const border = Color(0xFFE5E7EB);
  static const textPrimary = Color(0xFF1F2937);
  static const textMuted = Color(0xFF6B7280);
  static const orange = Color(0xFFFF6B00);
  static const orangeSoft = Color(0xFFFFF0E6);
  static const green = Color(0xFF00A86B);
  static const greenSoft = Color(0xFFE6F7F0);

  /// Legacy aliases used across POS widgets.
  static const accent = orange;
  static const accentSoft = orangeSoft;
  static const success = green;
  static const quickStrip = orangeSoft;

  /// Target share of row for cart on wide layouts (~32%).
  static const cartFlex = 32;
  static const menuFlex = 68;

  static const cartWidth = 420.0;
  static const cartWidthCompact = 340.0;
  static const cartWidthMin = 300.0;
  static const cartWidthMax = 460.0;

  static const categorySidebarWidth = 150.0;
  static const categorySidebarWidthCompact = 112.0;

  static const breakpoint = 780.0;
  static const mobileBreakpoint = 640.0;
  static const tabletMax = 1100.0;
  static const desktopMin = 1200.0;

  /// Merged shift + order-mode header (Foodics density).
  static const headerHeight = 45.0;
  static const headerMaroon = Color(0xFF6B1124);

  /// Menu grid: 4 columns by default so ~16+ tiles fit on screen.
  static int menuCrossAxisCount(double menuPaneWidth) {
    if (menuPaneWidth >= 1200) return 5;
    if (menuPaneWidth >= 480) return 4;
    return 2;
  }

  static double menuTileExtent(bool compact) => compact ? 118.0 : 124.0;

  static double cartWidthFor(double availableWidth) {
    final preferred = availableWidth * (cartFlex / 100);
    return preferred.clamp(cartWidthMin, cartWidthMax);
  }

  static double categoryWidthFor(double availableWidth) {
    if (availableWidth >= desktopMin) return categorySidebarWidth;
    return categorySidebarWidthCompact;
  }

  static bool isCompactPos(double availableWidth) =>
      availableWidth < desktopMin;

  /// Zero-latency page transitions for the cashier shell.
  static const pageTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: PosInstantPageTransitionsBuilder(),
      TargetPlatform.iOS: PosInstantPageTransitionsBuilder(),
      TargetPlatform.macOS: PosInstantPageTransitionsBuilder(),
      TargetPlatform.windows: PosInstantPageTransitionsBuilder(),
      TargetPlatform.linux: PosInstantPageTransitionsBuilder(),
      TargetPlatform.fuchsia: PosInstantPageTransitionsBuilder(),
    },
  );

  static BoxDecoration card({Color? color, double radius = 14}) => BoxDecoration(
        color: color ?? surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      );
}

/// Instant (no animation) page transitions for POS.
class PosInstantPageTransitionsBuilder extends PageTransitionsBuilder {
  const PosInstantPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
