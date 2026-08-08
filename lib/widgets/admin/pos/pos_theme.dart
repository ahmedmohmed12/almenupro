import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// Visual tokens for the redesigned POS experience.
abstract final class PosTheme {
  static const bg = Color(0xFFF3F5F8);
  static const surface = Colors.white;
  static const surfaceAlt = Color(0xFFF8FAFC);
  static const border = Color(0xFFE2E8F0);
  static const textMuted = Color(0xFF64748B);
  static const accent = AppTheme.brandMaroon;
  static const accentSoft = Color(0xFFFFF4F0);
  static const success = Color(0xFF059669);
  static const quickStrip = Color(0xFFFFF7ED);

  static const cartWidth = 400.0;
  static const categorySidebarWidth = 168.0;
  static const breakpoint = 1100.0;

  static BoxDecoration card({Color? color}) => BoxDecoration(
        color: color ?? surface,
        borderRadius: BorderRadius.circular(14),
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
