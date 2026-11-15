class AdminDeepLink {
  AdminDeepLink._();

  static const loginPath = '/login';
  static const orderPrefix = '/admin/orders';

  static String orderPath(String orderRef) {
    final ref = Uri.encodeComponent(orderRef.trim());
    return '$orderPrefix/$ref';
  }

  static const redirectQueryKeys = {
    'redirect',
    'redirectUrl',
    'returnUrl',
    'redirect_url',
    'return_url',
  };

  static String loginWithRedirect(String redirectPath) {
    final safe = sanitizeRedirect(redirectPath) ?? orderPrefix;
    return '$loginPath?redirect=${Uri.encodeQueryComponent(safe)}';
  }

  /// Only admin-relative paths. Hosts on absolute URLs are ignored (no open redirect).
  static String? sanitizeRedirect(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;

    Uri uri;
    try {
      uri = Uri.parse(value);
    } catch (_) {
      return null;
    }

    var path = uri.path.trim();
    if (path.isEmpty) return null;
    if (!path.startsWith('/')) path = '/$path';
    if (path.contains('..')) return null;
    if (path != loginPath &&
        path != '/admin' &&
        !path.startsWith('/admin/')) {
      return null;
    }
    if (path == loginPath) return '/admin';

    if (uri.hasQuery) {
      final filtered = Map<String, String>.from(uri.queryParameters);
      for (final key in redirectQueryKeys) {
        filtered.remove(key);
      }
      if (filtered.isNotEmpty) {
        return Uri(path: path, queryParameters: filtered).toString();
      }
    }
    return path;
  }

  static String? parseOrderRef(Uri uri) {
    final fromQuery = uri.queryParameters['order']?.trim() ??
        uri.queryParameters['orderId']?.trim() ??
        uri.queryParameters['id']?.trim();
    if (fromQuery != null && fromQuery.isNotEmpty) {
      return Uri.decodeComponent(fromQuery);
    }

    final segments =
        uri.path.split('/').where((segment) => segment.isNotEmpty).toList();
    if (segments.length >= 3 &&
        segments[0] == 'admin' &&
        segments[1] == 'orders') {
      final ref = Uri.decodeComponent(segments[2]).trim();
      return ref.isEmpty ? null : ref;
    }
    return null;
  }

  static String? parseRedirect(Uri uri) {
    for (final key in redirectQueryKeys) {
      final safe = sanitizeRedirect(uri.queryParameters[key]);
      if (safe != null) return safe;
    }
    return null;
  }

  static bool isLoginPath(String path) {
    final normalized = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    return normalized == loginPath;
  }

  static bool matchesOrder(String ref, {required String id, String? invoiceNumber}) {
    final needle = ref.trim();
    if (needle.isEmpty) return false;
    final clean = needle.startsWith('#') ? needle.substring(1) : needle;
    if (id == needle || id == clean) return true;
    final invoice = (invoiceNumber ?? '').trim();
    if (invoice.isEmpty) return false;
    final invoiceClean =
        invoice.startsWith('#') ? invoice.substring(1) : invoice;
    return invoice == needle ||
        invoice == clean ||
        invoiceClean == needle ||
        invoiceClean == clean;
  }
}
