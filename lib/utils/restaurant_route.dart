import 'package:flutter/foundation.dart';

import 'frontend_origin.dart';

/// Parses customer menu and link-hub URLs into a restaurant slug.
///
/// Supported patterns:
/// - `/menu/{slug}`
/// - `/restaurant/{slug}`
/// - `/r/{slug}` (menu alias)
/// - `/r/{slug}/links` (link-in-bio hub)
/// - `/menu/{slug}/links`
/// - `/{slug}`
/// - `?slug={slug}` (query fallback on web)
class RestaurantRoute {
  RestaurantRoute._();

  static const reservedSegments = {
    'admin',
    'login',
    'manager',
    'super-admin',
    'cashier',
    'legacy-menu',
    'menu',
    'order',
    'restaurants',
    'pos',
    'table',
    'driver',
    'r',
    'links',
    'index.html',
    'main.dart.js',
    'flutter.js',
    'flutter_service_worker.js',
    'manifest.json',
    'favicon.png',
    'icons',
    'assets',
    'canvaskit',
    'og',
  };

  static String normalizePath(String? path) {
    var route = (path ?? '').trim();
    if (route.endsWith('/') && route.length > 1) {
      route = route.substring(0, route.length - 1);
    }
    return route.isEmpty ? '/' : route;
  }

  static bool _looksLikeFile(String segment) {
    return segment.contains('.') && !segment.startsWith('.');
  }

  /// Returns slug when path is a link-hub page (`/r/{slug}/links` or
  /// `/menu/{slug}/links`).
  static String? parseLinkHubSlug(String? path) {
    final normalized = normalizePath(path);
    final segments =
        normalized.split('/').where((segment) => segment.isNotEmpty).toList();
    if (segments.length < 3) return null;
    final prefix = segments[0].toLowerCase();
    final slug = segments[1].toLowerCase();
    final tail = segments[2].toLowerCase();
    if (tail != 'links') return null;
    if (prefix != 'r' && prefix != 'menu') return null;
    if (slug.isEmpty || reservedSegments.contains(slug) || _looksLikeFile(slug)) {
      return null;
    }
    return slug;
  }

  static String? parseSlug(String? path, {Map<String, String>? query}) {
    final fromQuery = query?['slug']?.trim();
    if (fromQuery != null && fromQuery.isNotEmpty) {
      return fromQuery.toLowerCase();
    }

    final normalized = normalizePath(path);
    if (normalized == '/') return null;

    final segments =
        normalized.split('/').where((segment) => segment.isNotEmpty).toList();
    if (segments.isEmpty) return null;

    if (segments.length == 1) {
      final slug = segments.first.toLowerCase();
      if (reservedSegments.contains(slug) || _looksLikeFile(slug)) return null;
      return slug;
    }

    if (segments.length >= 2) {
      final prefix = segments.first.toLowerCase();
      if (prefix == 'menu' || prefix == 'restaurant' || prefix == 'r') {
        // `/r/{slug}/links` is not a menu page.
        if (segments.length >= 3 && segments[2].toLowerCase() == 'links') {
          return null;
        }
        final slug = segments[1].toLowerCase();
        if (slug.isEmpty ||
            reservedSegments.contains(slug) ||
            _looksLikeFile(slug)) {
          return null;
        }
        return slug;
      }
    }

    return null;
  }

  /// Reads the restaurant slug from the live browser URL (Instagram in-app
  /// browsers often start Flutter at `/` even when the address has a slug).
  static String? slugFromBrowserLocation() {
    if (!kIsWeb) return null;
    final uri = Uri.base;
    return parseSlug(uri.path, query: uri.queryParameters) ??
        parseLinkHubSlug(uri.path);
  }

  /// Canonical customer menu URL path for a slug.
  static String menuPathForSlug(String slug) =>
      '/r/${slug.trim().toLowerCase()}';

  /// Canonical link-in-bio hub path.
  static String linksPathForSlug(String slug) =>
      '/r/${slug.trim().toLowerCase()}/links';

  /// Absolute public hub URL for sharing / QR.
  static String publicLinksUrl(String slug, {String? origin}) {
    final base = FrontendOrigin.resolve(override: origin);
    return '$base${linksPathForSlug(slug)}';
  }
}
