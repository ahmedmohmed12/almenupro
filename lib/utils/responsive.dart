import 'package:flutter/material.dart';

class ResponsiveLayout {
  static const double desktopBreakpoint = 900;

  static bool isDesktop(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= desktopBreakpoint;
  }
}
