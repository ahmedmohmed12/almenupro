import 'package:flutter/material.dart';

/// Burgundy / gold admin sign-in styling shared across role login routes.
class AdminLoginTheme {
  AdminLoginTheme._();

  static const burgundy = Color(0xFF6B1124);
  static const gold = Color(0xFFD4A84B);
  static const canvas = Color(0xFFF4F6F8);

  static InputDecoration fieldDecoration({
    required String label,
    String? hint,
    String? error,
    Widget? trailingIcon,
    Widget? leadingIcon,
  }) {
    const radius = BorderRadius.all(Radius.circular(14));
    final border = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: burgundy.withValues(alpha: 0.25)),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: error,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      filled: true,
      fillColor: Colors.white,
      prefixIcon: leadingIcon,
      suffixIcon: trailingIcon,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: burgundy, width: 1.6),
      ),
      enabledBorder: border,
      errorBorder: border.copyWith(
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: border.copyWith(
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
      ),
    );
  }

  static ButtonStyle primaryButton({bool disabled = false}) {
    return ElevatedButton.styleFrom(
      backgroundColor: burgundy,
      disabledBackgroundColor: burgundy.withValues(alpha: 0.45),
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: disabled ? 0 : 2,
    );
  }
}