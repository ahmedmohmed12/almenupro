import 'package:flutter/foundation.dart';

/// Runtime profile for AlMenuPro POS (Web PWA vs Native Desktop).
///
/// Keeps platform branching in one place so cashiers share the same UI code.
abstract final class PosPlatformProfile {
  static bool get isWeb => kIsWeb;
  static bool get isNativeDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// Web uses IndexedDB + Service Worker; native uses prefs-backed offline store.
  static String get storageBackendLabel =>
      isWeb ? 'indexed_db+prefs_drafts' : 'prefs_native_store';

  /// PWA / SW only apply on web.
  static bool get usesServiceWorker => isWeb;

  /// Direct USB / serial hardware hooks are native-only.
  static bool get usesNativeHardwareHooks => isNativeDesktop;
}
