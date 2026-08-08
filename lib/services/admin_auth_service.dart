import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/admin_role.dart';
import '../models/restaurant.dart';
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

  Future<void> logout() async {
    _session = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
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
      }),
    );
  }
}
