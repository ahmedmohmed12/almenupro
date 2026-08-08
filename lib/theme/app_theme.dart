import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Almenupro brand palette from logo:
/// - Orange → "Almenu" + checkmark
/// - Maroon → "pro" + ring icon
class AppTheme {
  static const Color brandOrange = Color(0xFFE39000);
  static const Color brandMaroon = Color(0xFF7B241C);
  static const Color brandBlack = Color(0xFF1A1A1A);
  static const Color brandSurface = Color(0xFFFAF7F4);
  static const Color brandBackground = Color(0xFFF5F0EB);

  static const Color brandPrimary = brandOrange;
  static const Color brandSecondary = brandMaroon;

  static ThemeData light() {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: brandOrange,
      onPrimary: Colors.white,
      secondary: brandMaroon,
      onSecondary: Colors.white,
      error: const Color(0xFFB3261E),
      onError: Colors.white,
      surface: brandSurface,
      onSurface: brandBlack,
      onSurfaceVariant: const Color(0xFF5C4A42),
      outline: brandMaroon.withValues(alpha: 0.25),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: brandBackground,
    );

    return base.copyWith(
      textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).apply(
        bodyColor: brandBlack,
        displayColor: brandBlack,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: brandMaroon,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: brandMaroon.withValues(alpha: 0.12)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brandOrange,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandMaroon,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return brandMaroon;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return brandOrange;
            }
            return Colors.white;
          }),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: brandOrange, width: 2),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: brandMaroon.withValues(alpha: 0.25)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: brandOrange.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.all(
          GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
