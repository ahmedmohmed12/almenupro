import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/customer_checkout_profile.dart';
import '../utils/whatsapp_phone.dart';

class CustomerCheckoutCacheService {
  CustomerCheckoutCacheService._();

  static final CustomerCheckoutCacheService instance =
      CustomerCheckoutCacheService._();

  static const _profilePrefix = 'checkout_profile_';
  static const _lastPhonePrefix = 'checkout_last_phone_';

  String _profileKey(String restaurantId, String phone) {
    final digits = WhatsAppPhone.digitsOnly(phone);
    return '$_profilePrefix${restaurantId}_$digits';
  }

  String _lastPhoneKey(String restaurantId) => '$_lastPhonePrefix$restaurantId';

  Future<CustomerCheckoutProfile?> loadProfile(
    String restaurantId,
    String phone,
  ) async {
    final digits = WhatsAppPhone.digitsOnly(phone);
    if (digits.length < 8) return null;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileKey(restaurantId, digits));
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final profile = CustomerCheckoutProfile.fromMap(
        Map<String, dynamic>.from(decoded),
      );
      return profile.hasUsableData ? profile : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProfile(
    String restaurantId,
    CustomerCheckoutProfile profile,
  ) async {
    final digits = WhatsAppPhone.digitsOnly(profile.phone);
    if (digits.length < 8) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _profileKey(restaurantId, digits),
      jsonEncode(profile.toMap()),
    );
    await prefs.setString(_lastPhoneKey(restaurantId), profile.phone.trim());
  }

  Future<String?> loadLastPhone(String restaurantId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastPhoneKey(restaurantId));
  }
}
