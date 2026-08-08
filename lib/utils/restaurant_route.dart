/// Parses customer menu URLs into a restaurant slug.
///
/// Supported patterns:
/// - `/menu/{slug}`
/// - `/restaurant/{slug}`
/// - `/{slug}`
/// - `?slug={slug}` (query fallback on web)
class RestaurantRoute {
  RestaurantRoute._();

  static const reservedSegments = {
    'admin',
    'legacy-menu',
    'menu',
    'restaurant',
  };

  static String normalizePath(String? path) {
    var route = (path ?? '').trim();
    if (route.endsWith('/') && route.length > 1) {
      route = route.substring(0, route.length - 1);
    }
    return route.isEmpty ? '/' : route;
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
      if (reservedSegments.contains(slug)) return null;
      return slug;
    }

    if (segments.length >= 2) {
      final prefix = segments.first.toLowerCase();
      if (prefix == 'menu' || prefix == 'restaurant') {
        final slug = segments[1].toLowerCase();
        return slug.isEmpty ? null : slug;
      }
    }

    return null;
  }

  /// Canonical customer menu URL path for a slug.
  static String menuPathForSlug(String slug) => '/menu/${slug.trim().toLowerCase()}';
}
