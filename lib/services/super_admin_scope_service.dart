import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/restaurant.dart';
import 'admin_auth_service.dart';
import 'api_service.dart';

const _selectedRestaurantKey = 'super_admin_selected_restaurant';

/// Tracks which restaurant a Super Admin is currently managing in the dashboard.
class SuperAdminScopeService extends ChangeNotifier {
  SuperAdminScopeService._();

  static final SuperAdminScopeService instance = SuperAdminScopeService._();

  String? _selectedRestaurantId;
  String? _selectedRestaurantName;
  List<Restaurant> _restaurants = [];
  var _loadingRestaurants = false;

  String? get selectedRestaurantId => _selectedRestaurantId;
  String? get selectedRestaurantName => _selectedRestaurantName;
  List<Restaurant> get restaurants => List.unmodifiable(_restaurants);
  bool get loadingRestaurants => _loadingRestaurants;
  bool get hasSelection =>
      _selectedRestaurantId != null && _selectedRestaurantId!.isNotEmpty;

  String get effectiveRestaurantId =>
      AdminAuthService.instance.isRestaurantAdmin
          ? (AdminAuthService.instance.restaurantId ??
              ApiService.defaultRestaurantId)
          : (_selectedRestaurantId ?? ApiService.defaultRestaurantId);

  Map<String, String> get scopeHeaders {
    if (!AdminAuthService.instance.isSuperAdmin || !hasSelection) {
      return const {};
    }
    return {'X-Restaurant-Id': _selectedRestaurantId!};
  }

  Future<void> initialize() async {
    if (!AdminAuthService.instance.isSuperAdmin) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_selectedRestaurantKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _selectedRestaurantId = decoded['id']?.toString();
      _selectedRestaurantName = decoded['name']?.toString();
    } catch (_) {
      _selectedRestaurantId = null;
      _selectedRestaurantName = null;
    }
  }

  Future<void> refreshRestaurants() async {
    if (!AdminAuthService.instance.isSuperAdmin) return;

    _loadingRestaurants = true;
    notifyListeners();

    try {
      _restaurants = await ApiService.instance.fetchRestaurants();
      if (_selectedRestaurantId != null &&
          !_restaurants.any((entry) => entry.id == _selectedRestaurantId)) {
        await clearSelection();
      } else if (_selectedRestaurantId == null && _restaurants.isNotEmpty) {
        await selectRestaurant(_restaurants.first);
      } else if (_selectedRestaurantId != null) {
        final match = _restaurants.firstWhere(
          (entry) => entry.id == _selectedRestaurantId,
          orElse: () => Restaurant(
            id: _selectedRestaurantId!,
            slug: '',
            name: _selectedRestaurantName ?? _selectedRestaurantId!,
          ),
        );
        _selectedRestaurantName = match.name;
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('SuperAdminScopeService.refreshRestaurants failed: $error');
      }
    } finally {
      _loadingRestaurants = false;
      notifyListeners();
    }
  }

  Future<void> selectRestaurant(Restaurant restaurant) async {
    _selectedRestaurantId = restaurant.id;
    _selectedRestaurantName = restaurant.name;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _selectedRestaurantKey,
      jsonEncode({'id': restaurant.id, 'name': restaurant.name}),
    );
    notifyListeners();
  }

  Future<void> clearSelection() async {
    _selectedRestaurantId = null;
    _selectedRestaurantName = null;
    _restaurants = [];

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selectedRestaurantKey);
    notifyListeners();
  }
}
