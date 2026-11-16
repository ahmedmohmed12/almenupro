import 'package:flutter/foundation.dart';

/// Public site origin for deep links, WhatsApp, and QR (no trailing slash).
abstract final class FrontendOrigin {
  static const defaultOrigin = String.fromEnvironment(
    'FRONTEND_BASE_URL',
    defaultValue: 'https://u-menus.com',
  );

  static String resolve({String? override}) {
    final custom = override?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom.replaceAll(RegExp(r'/+$'), '');
    }
    if (kIsWeb) {
      return Uri.base.origin.replaceAll(RegExp(r'/+$'), '');
    }
    return defaultOrigin.replaceAll(RegExp(r'/+$'), '');
  }
}