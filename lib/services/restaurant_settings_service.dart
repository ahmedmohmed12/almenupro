import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/invoice_language.dart';
import '../models/loyalty_cashback.dart';
import '../models/payment_method_config.dart';
import '../models/restaurant_settings.dart';
import '../models/sales_platform_config.dart';
import '../models/working_hours.dart';
import '../utils/firebase_config.dart';
import '../utils/whatsapp_phone.dart';
import 'api_service.dart';
import 'super_admin_scope_service.dart';

const _cacheKey = 'restaurant_settings_cache';

class RestaurantSettingsService {
  RestaurantSettingsService._();

  static final RestaurantSettingsService instance = RestaurantSettingsService._();

  RestaurantSettings? _cached;

  RestaurantSettings? get cached => _cached;

  Future<RestaurantSettings> load({String? restaurantId}) async {
    try {
      final remote = await ApiService.instance.fetchSettings(
        restaurantId: restaurantId,
      );
      _cached = remote;
      await _saveCache(remote);
      return remote;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('RestaurantSettingsService.load remote failed: $error');
      }
    }

    final local = await _loadCache();
    if (local != null) {
      _cached = local;
      return local;
    }

    if (isFirebaseConfigured) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('restaurants')
            .doc(restaurantId)
            .collection('settings')
            .doc('restaurant_info')
            .get();
        if (doc.exists && doc.data() != null) {
          final settings = RestaurantSettings.fromJson(doc.data()!);
          _cached = settings;
          await _saveCache(settings);
          return settings;
        }
      } catch (error) {
        if (kDebugMode) {
          debugPrint('RestaurantSettingsService.load firebase failed: $error');
        }
      }
    }

    _cached = RestaurantSettings.defaults();
    return _cached!;
  }

  Future<void> saveWorkingHours(WorkingHoursSettings workingHours) async {
    final current = _cached ?? await load();
    await _persist(
      current.copyWith(
        workingHours: workingHours,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// Saves WhatsApp number using split country/phone fields.
  Future<void> saveWhatsappNumber({
    String? countryCode,
    String? phone,
    String? restaurantId,
    String? whatsappNumber,
  }) async {
    final scopedRestaurantId = restaurantId ??
        SuperAdminScopeService.instance.effectiveRestaurantId;
    final current = _cached ?? await load(restaurantId: scopedRestaurantId);

    final nextCountry = countryCode ?? current.whatsappCountryCode;
    final nextPhone = phone ?? current.whatsappPhone;
    final nextNumber = (countryCode != null || phone != null)
        ? WhatsAppPhone.combine(nextCountry, nextPhone)
        : (whatsappNumber ?? current.whatsappNumber).trim();

    await _persist(
      current.copyWith(
        whatsappCountryCode: nextCountry,
        whatsappPhone: (countryCode != null || phone != null)
            ? WhatsAppPhone.digitsOnly(nextPhone)
            : current.whatsappPhone,
        whatsappNumber: nextNumber,
        updatedAt: DateTime.now().toUtc(),
      ),
      restaurantId: scopedRestaurantId,
    );
  }

  Future<void> saveUpsellSettings({
    bool? smartUpsellEnabled,
    double? freeDeliveryThreshold,
    double? impulseBumpMaxPrice,
    List<int>? impulseBumpItemIds,
    bool? smartRecommendationsEnabled,
    String? restaurantId,
  }) async {
    final current = _cached ?? await load(restaurantId: restaurantId);
    await _persist(
      current.copyWith(
        smartUpsellEnabled: smartUpsellEnabled,
        freeDeliveryThreshold: freeDeliveryThreshold,
        impulseBumpMaxPrice: impulseBumpMaxPrice,
        impulseBumpItemIds: impulseBumpItemIds,
        smartRecommendationsEnabled: smartRecommendationsEnabled,
        updatedAt: DateTime.now().toUtc(),
      ),
      restaurantId: restaurantId,
    );
  }

  Future<void> saveStage3UpsellSettings({
    required bool smartCartUpsellEnabled,
    required bool smartUpsellDrinksEnabled,
    required bool smartUpsellSidesEnabled,
    required bool smartUpsellDessertsEnabled,
    required double dessertUpsellThreshold,
    String? restaurantId,
  }) async {
    final current = _cached ?? await load(restaurantId: restaurantId);
    await _persist(
      current.copyWith(
        smartCartUpsellEnabled: smartCartUpsellEnabled,
        smartUpsellDrinksEnabled: smartUpsellDrinksEnabled,
        smartUpsellSidesEnabled: smartUpsellSidesEnabled,
        smartUpsellDessertsEnabled: smartUpsellDessertsEnabled,
        dessertUpsellThreshold: dessertUpsellThreshold,
        updatedAt: DateTime.now().toUtc(),
      ),
      restaurantId: restaurantId,
    );
  }

  Future<void> saveLoyaltySettings({
    required CashbackType cashbackType,
    required double cashbackValue,
    required double minOrderForLoyalty,
    String? restaurantId,
  }) async {
    final current = _cached ?? await load(restaurantId: restaurantId);
    await _persist(
      current.copyWith(
        cashbackType: cashbackType,
        cashbackValue: cashbackValue,
        minOrderForLoyalty: minOrderForLoyalty,
        updatedAt: DateTime.now().toUtc(),
      ),
      restaurantId: restaurantId,
    );
  }

  Future<void> savePaymentMethods({
    required List<PaymentMethodConfig> paymentMethods,
    String? restaurantId,
  }) async {
    final current = _cached ?? await load(restaurantId: restaurantId);
    await _persist(
      current.copyWith(
        paymentMethods: paymentMethods,
        updatedAt: DateTime.now().toUtc(),
      ),
      restaurantId: restaurantId,
    );
  }

  Future<void> saveSalesPlatforms({
    required List<SalesPlatformConfig> salesPlatforms,
    String? restaurantId,
  }) async {
    final current = _cached ?? await load(restaurantId: restaurantId);
    await _persist(
      current.copyWith(
        salesPlatforms: salesPlatforms,
        updatedAt: DateTime.now().toUtc(),
      ),
      restaurantId: restaurantId,
    );
  }

  Future<void> savePosSettings(
    RestaurantSettings settings, {
    String? restaurantId,
  }) async {
    await _persist(
      settings.copyWith(updatedAt: DateTime.now().toUtc()),
      restaurantId: restaurantId,
    );
  }

  Future<void> saveStoreProfile({
    required String logoUrl,
    required String restaurantDescription,
    String? restaurantId,
  }) async {
    final current = _cached ?? await load(restaurantId: restaurantId);
    await _persist(
      current.copyWith(
        logoUrl: logoUrl.trim(),
        restaurantDescription: restaurantDescription.trim(),
        updatedAt: DateTime.now().toUtc(),
      ),
      restaurantId: restaurantId,
    );
  }

  Future<void> saveInvoiceLanguage({
    required InvoiceLanguage invoiceLanguage,
    String? restaurantId,
  }) async {
    final scopedRestaurantId = restaurantId ??
        SuperAdminScopeService.instance.effectiveRestaurantId;
    final current = _cached ?? await load(restaurantId: scopedRestaurantId);
    await _persist(
      current.copyWith(
        invoiceLanguage: invoiceLanguage,
        updatedAt: DateTime.now().toUtc(),
      ),
      restaurantId: scopedRestaurantId,
    );
  }

  Future<void> saveEmailNotifications({
    required String notificationEmail,
    required bool notifyOnNewOrderEmail,
    required bool notifyOnShiftCloseEmail,
    String? restaurantId,
  }) async {
    final current = _cached ?? await load(restaurantId: restaurantId);
    await _persist(
      current.copyWith(
        notificationEmail: notificationEmail.trim(),
        notifyOnNewOrderEmail: notifyOnNewOrderEmail,
        notifyOnShiftCloseEmail: notifyOnShiftCloseEmail,
        updatedAt: DateTime.now().toUtc(),
      ),
      restaurantId: restaurantId,
    );
  }

  Future<void> clearCache() async {
    _cached = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
  }

  Future<void> _persist(
    RestaurantSettings settings, {
    String? restaurantId,
  }) async {
    await ApiService.instance.updateSettings(
      settings,
      restaurantId: restaurantId,
    );
    _cached = settings;
    await _saveCache(settings);
    await _syncFirebase(settings);
  }

  Future<void> _syncFirebase(RestaurantSettings settings) async {
    if (!isFirebaseConfigured) return;
    try {
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('restaurant_info')
          .set(settings.toJson(), SetOptions(merge: true));
    } catch (error) {
      if (kDebugMode) {
        debugPrint('RestaurantSettingsService firebase sync failed: $error');
      }
    }
  }

  Future<void> _saveCache(RestaurantSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(settings.toJson()));
  }

  Future<RestaurantSettings?> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return RestaurantSettings.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }
}
