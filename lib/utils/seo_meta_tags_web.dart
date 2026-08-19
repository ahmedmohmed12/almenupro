import 'dart:html' as html;

import '../utils/image_url.dart';
import 'restaurant_route.dart';

class SeoMetaTags {
  SeoMetaTags._();

  static void updateRestaurantMenu({
    required String slug,
    required String name,
    String? description,
    String? logoUrl,
    String? siteOrigin,
  }) {
    final cleanSlug = slug.trim().toLowerCase();
    final cleanName = name.trim();
    if (cleanSlug.isEmpty || cleanName.isEmpty) return;

    final origin = (siteOrigin ?? _currentOrigin()).replaceAll(RegExp(r'/+$'), '');
    final menuPath = RestaurantRoute.menuPathForSlug(cleanSlug);
    final canonicalUrl = '$origin$menuPath';
    final metaDescription = (description?.trim().isNotEmpty == true)
        ? description!.trim()
        : 'منيو مطعم $cleanName لطلب الوجبات أونلاين';
    final ogDescription = (description?.trim().isNotEmpty == true)
        ? description!.trim()
        : 'اطلب الآن من منيو $cleanName';
    final imageUrl = _resolveOgImage(logoUrl, origin);

    html.document.title = '$cleanName — المنيو الإلكتروني';
    _setMetaName('description', metaDescription);
    _setMetaProperty('og:url', canonicalUrl);
    _setMetaProperty('og:type', 'website');
    _setMetaProperty('og:title', cleanName);
    _setMetaProperty('og:description', ogDescription);
    _setMetaProperty('og:image', imageUrl);
    _setMetaProperty('og:image:width', '300');
    _setMetaProperty('og:image:height', '300');
    _setMetaName('twitter:card', 'summary_large_image');
    _setMetaName('twitter:title', cleanName);
    _setMetaName('twitter:description', metaDescription);
    _setMetaName('twitter:image', imageUrl);
    _setCanonical(canonicalUrl);
  }

  static String _currentOrigin() {
    return html.window.location.origin;
  }

  static String _resolveOgImage(String? logoUrl, String frontendOrigin) {
    final fallback = '$frontendOrigin/icons/Icon-512.png';
    final raw = logoUrl?.trim() ?? '';
    if (raw.isEmpty) return fallback;

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }

    if (raw.startsWith('/menu-images/') ||
        raw.startsWith('/api/uploads/menu/') ||
        raw.contains('/api/image-proxy')) {
      return resolveImageUrl(raw);
    }

    if (raw.startsWith('/')) {
      return '$frontendOrigin$raw';
    }

    return resolveImageUrl(raw);
  }

  static void _setMetaName(String name, String content) {
    final selector = 'meta[name="$name"]';
    html.Element? element = html.document.querySelector(selector);
    if (element == null) {
      element = html.MetaElement()..name = name;
      html.document.head?.append(element);
    }
    element.setAttribute('content', content);
  }

  static void _setMetaProperty(String property, String content) {
    final selector = 'meta[property="$property"]';
    html.Element? element = html.document.querySelector(selector);
    if (element == null) {
      element = html.MetaElement()..setAttribute('property', property);
      html.document.head?.append(element);
    }
    element.setAttribute('content', content);
  }

  static void _setCanonical(String href) {
    html.Element? element = html.document.querySelector('link[rel="canonical"]');
    if (element == null) {
      element = html.LinkElement()..rel = 'canonical';
      html.document.head?.append(element);
    }
    element.setAttribute('href', href);
  }
}
