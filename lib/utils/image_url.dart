import '../services/api_service.dart';

/// API origin without the `/api` suffix, e.g. https://almenupro-backend-1.onrender.com
String get menuImageApiOrigin {
  final base = ApiService.baseUrl;
  if (base.endsWith('/api')) {
    return base.substring(0, base.length - 4);
  }
  return base.replaceAll(RegExp(r'/api/?$'), '');
}

bool isLegacyTalabatImageUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return false;
  final host = uri.host.toLowerCase();
  return host.contains('deliveryhero.io') ||
      host.contains('talabat.com') ||
      host.contains('cloudinary.com') ||
      host.contains('googleusercontent.com') ||
      host.contains('fbcdn.net') ||
      host.contains('cdninstagram.com') ||
      host.contains('instagram.com');
}

bool isLocalMenuImagePath(String url) {
  final trimmed = url.trim();
  return trimmed.startsWith('/menu-images/') ||
      trimmed.startsWith('/api/uploads/menu/');
}

bool isBackendImageProxyPath(String url) {
  return url.trim().contains('/api/image-proxy');
}

String? localMenuImageFilename(String url) {
  final trimmed = url.trim();
  if (!isLocalMenuImagePath(trimmed)) return null;
  final parts = trimmed.split('/');
  return parts.isEmpty ? null : parts.last;
}

Object? firstNonEmptyImageField(Map json) {
  for (final key in [
    'image_url',
    'imageUrl',
    'image',
    'photo',
    'thumbnail',
    'thumbnail_url',
  ]) {
    final value = json[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty && text != 'null') return value;
  }
  return null;
}

/// Builds a browser-loadable image URL from API payloads or stored paths.
String resolveImageUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty || trimmed == 'null' || trimmed.startsWith('data:')) {
    return '';
  }

  if (isBackendImageProxyPath(trimmed)) {
    return trimmed.startsWith('/')
        ? '$menuImageApiOrigin$trimmed'
        : trimmed;
  }

  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    if (isLegacyTalabatImageUrl(trimmed)) {
      return '$menuImageApiOrigin/api/image-proxy?url=${Uri.encodeComponent(trimmed)}';
    }
    return trimmed;
  }

  final filename = localMenuImageFilename(trimmed);
  if (filename != null && filename.isNotEmpty) {
    return '$menuImageApiOrigin/menu-images/$filename';
  }

  if (trimmed.startsWith('/')) {
    return '$menuImageApiOrigin$trimmed';
  }

  return trimmed;
}

/// Parses API payloads — keeps local paths, proxy paths, and absolute URLs.
String normalizeMenuImageUrl(Object? raw) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty || value == 'null' || value.startsWith('data:')) return '';
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return value;
  }
  if (isLocalMenuImagePath(value)) return value;
  if (isBackendImageProxyPath(value)) return value;
  if (isLegacyTalabatImageUrl(value)) return value;
  return value;
}
