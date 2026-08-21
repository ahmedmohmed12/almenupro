import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/admin_role.dart';
import '../models/restaurant.dart';
import '../models/staff_user.dart';
import 'api_service.dart';

const _sessionKey = 'admin_auth_session';

class AdminAuthService {
  AdminAuthService._();

  static final AdminAuthService instance = AdminAuthService._();

  AdminSession? _session;

  AdminSession? get session => _session;
  bool get isLoggedIn => _session != null && _session!.token.isNotEmpty;
  bool get isSuperAdmin => _session?.isSuperAdmin ?? false;
  bool get isRestaurantAdmin => _session?.isRestaurantAdmin ?? false;
  bool get isCashier => _session?.isCashier ?? false;
  String? get restaurantId => _session?.restaurantId;
  String? get restaurantName => _session?.restaurantName;
  String? get token => _session?.token;

  Map<String, String> get authHeaders {
    if (_session == null) return const {};
    return {'Authorization': 'Bearer ${_session!.token}'};
  }

  Future<void> initialize() async {
    if (_session != null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _session = AdminSession.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      _session = null;
    }
  }

  Future<AdminSession> loginSuperAdmin({
    required String username,
    required String password,
  }) async {
    final session = await ApiService.instance.loginAdmin(
      username: username,
      password: password,
    );
    await _persist(session);
    return session;
  }

  Future<AdminSession> loginRestaurantAdmin({
    required String restaurantSlug,
    required String password,
  }) async {
    final session = await ApiService.instance.loginAdmin(
      restaurantSlug: restaurantSlug,
      password: password,
    );
    await _persist(session);
    return session;
  }

  Future<({AdminSession session, PosCashierSession cashierSession})> loginCashier({
    required String restaurantName,
    required String cashierName,
    required String password,
  }) async {
    final result = await ApiService.instance.loginCashier(
      restaurantName: restaurantName,
      cashierName: cashierName,
      pin: password,
    );
    await _persist(result.session);
    await persistCashierPermissions(
      result.cashierSession.permissions,
      roleId: result.cashierSession.roleId,
    );
    return result;
  }

  Future<void> logout() async {
    _session = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    await prefs.remove('${_sessionKey}_cashier_permissions');
  }

  Future<({Map<String, bool> permissions, String roleId})?> loadCashierPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${_sessionKey}_cashier_permissions');
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final permissions = <String, bool>{};
      final rawPermissions = decoded['permissions'];
      if (rawPermissions is Map) {
        rawPermissions.forEach((key, value) {
          permissions[key.toString()] = value == true;
        });
      }
      return (
        permissions: permissions,
        roleId: decoded['roleId']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> persistCashierPermissions(
    Map<String, bool> permissions, {
    String? roleId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '${_sessionKey}_cashier_permissions',
      jsonEncode({
        'roleId': roleId ?? '',
        'permissions': permissions,
      }),
    );
  }

  Future<void> _persist(AdminSession session) async {
    _session = session;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sessionKey,
      jsonEncode({
        'token': session.token,
        'role': session.role.storageKey,
        'restaurantId': session.restaurantId,
        'restaurantName': session.restaurantName,
        'staffId': session.staffId,
        'staffName': session.staffName,
      }),
    );
  }
}
