import '../services/api_service.dart';

/// API origin without the `/api` suffix, e.g. https://almenupro-backend.vercel.app
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
  return host.contains('deliveryhero.io') || host.contains('talabat.com');
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

/// Builds a browser-loadable image URL from API payloads or stored paths.
String resolveImageUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return trimmed;

  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }

  if (isBackendImageProxyPath(trimmed)) {
    return trimmed.startsWith('/')
        ? '$menuImageApiOrigin$trimmed'
        : trimmed;
  }

  final filename = localMenuImageFilename(trimmed);
  if (filename != null && filename.isNotEmpty) {
    return '$menuImageApiOrigin/menu-images/$filename';
  }

  if (isLegacyTalabatImageUrl(trimmed)) {
    return '$menuImageApiOrigin/api/image-proxy?url=${Uri.encodeComponent(trimmed)}';
  }

  if (trimmed.startsWith('/')) {
    return '$menuImageApiOrigin$trimmed';
  }

  return trimmed;
}

/// Parses API payloads — keeps local paths, proxy paths, and absolute URLs.
String normalizeMenuImageUrl(Object? raw) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty) return '';
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return value;
  }
  if (isLocalMenuImagePath(value)) return value;
  if (isBackendImageProxyPath(value)) return value;
  if (isLegacyTalabatImageUrl(value)) return value;
  return value;
}
