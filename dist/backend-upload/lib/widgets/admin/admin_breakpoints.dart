import 'package:flutter/material.dart';

/// Shared breakpoints for admin dashboard layouts (Flutter Web).
class AdminBreakpoints {
  AdminBreakpoints._();

  static const double compact = 600;
  static const double mobile = 900;
  static const double tablet = 1100;
  static const double laptop = 1280;
  static const double desktop = 1536;

  static double widthOf(BuildContext context) => MediaQuery.sizeOf(context).width;

  static bool isCompact(BuildContext context) => widthOf(context) < compact;

  static bool isMobile(BuildContext context) => widthOf(context) < mobile;

  static bool isTablet(BuildContext context) =>
      widthOf(context) >= mobile && widthOf(context) < tablet;

  static bool isLaptop(BuildContext context) =>
      widthOf(context) >= tablet && widthOf(context) < laptop;

  /// Content area with sidebar open — treat as narrow below tablet.
  static bool isNarrowContent(BuildContext context) => widthOf(context) < tablet;

  static bool isWide(BuildContext context) => widthOf(context) >= tablet;

  static double pagePadding(BuildContext context) {
    if (isCompact(context)) return 12;
    if (isMobile(context)) return 16;
    return 24;
  }

  static int gridColumnCount(double maxWidth, {double minTileWidth = 200}) {
    if (maxWidth <= 0 || !maxWidth.isFinite) return 1;
    final columns = (maxWidth / minTileWidth).floor();
    return columns.clamp(1, 4);
  }
}
