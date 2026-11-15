class AuthLoginRoutes {
  AuthLoginRoutes._();

  static const superAdmin = '/super-admin/login';
  static const manager = '/manager/login';
  static const pos = '/pos/login';
  static const cashier = '/cashier/login';

  /// Legacy alias; redirects to [manager].
  static const legacyLogin = '/login';

  static const posPaths = {pos, cashier};

  static bool isDedicatedLoginPath(String path) {
    final normalized = _normalize(path);
    return normalized == legacyLogin ||
        normalized == superAdmin ||
        normalized == manager ||
        posPaths.contains(normalized);
  }

  static bool isAdminShellPath(String path) {
    final normalized = _normalize(path);
    return normalized == '/admin' || normalized.startsWith('/admin/');
  }

  /// Paths that must never fall through to the customer restaurant directory.
  static bool isStaffPath(String path) {
    return isDedicatedLoginPath(path) || isAdminShellPath(path);
  }

  static String _normalize(String path) {
    var value = path.trim();
    if (value.endsWith('/') && value.length > 1) {
      value = value.substring(0, value.length - 1);
    }
    return value.isEmpty ? '/' : value;
  }
}