import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/invoice_language.dart';
import '../models/link_hub_config.dart';
import '../models/loyalty_cashback.dart';
import '../models/payment_method_config.dart';
import '../models/restaurant_settings.dart';
import '../models/sales_platform_config.dart';
import '../models/working_hours.dart';
import '../utils/firebase_config.dart';
import '../utils/whatsapp_phone.dart';
import 'api_service.dart';
import 'super_admin_scope_service.dart';

class RestaurantSettingsService extends ChangeNotifier {
  RestaurantSettingsService._();

  static final RestaurantSettingsService instance = RestaurantSettingsService._();

  RestaurantSettings? _cached;
  String? _cachedRestaurantId;

  RestaurantSettings? get cached => _cached;
  String? get cachedRestaurantId => _cachedRestaurantId;

  String _prefsKey(String? restaurantId) {
    final id = (restaurantId ?? '').trim();
    return id.isEmpty
        ? 'restaurant_settings_cache'
        : 'restaurant_settings_cache_$id';
  }

  Future<RestaurantSettings> load({String? restaurantId}) async {
    final scopedId = (restaurantId ??
            SuperAdminScopeService.instance.effectiveRestaurantId)
        .trim();
    try {
      final remote = await ApiService.instance.fetchSettings(
        restaurantId: scopedId.isEmpty ? restaurantId : scopedId,
      );
      _setCache(remote, scopedId);
      await _saveCache(remote, scopedId);
      return remote;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('RestaurantSettingsService.load remote failed: $error');
      }
    }

    final local = await _loadCache(scopedId);
    if (local != null) {
      _setCache(local, scopedId);
      return local;
    }

    if (isFirebaseConfigured) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('restaurants')
            .doc(scopedId.isEmpty ? restaurantId : scopedId)
            .collection('settings')
            .doc('restaurant_info')
            .get();
        if (doc.exists && doc.data() != null) {
          final settings = RestaurantSettings.fromJson(doc.data()!);
          _setCache(settings, scopedId);
          await _saveCache(settings, scopedId);
          return settings;
        }
      } catch (error) {
        if (kDebugMode) {
          debugPrint('RestaurantSettingsService.load firebase failed: $error');
        }
      }
    }

    final fallback = RestaurantSettings.defaults();
    _setCache(fallback, scopedId);
    return fallback;
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
    final scopedId = (restaurantId ??
            SuperAdminScopeService.instance.effectiveRestaurantId)
        .trim();
    final effectiveId = scopedId.isEmpty ? restaurantId : scopedId;
    final mergedLocal = PlatformCatalog.mergeWithDefaults(salesPlatforms);
    final current = _cached ?? await load(restaurantId: effectiveId);
    List<SalesPlatformConfig> merged = mergedLocal;
    try {
      final saved = await ApiService.instance.putSalesPlatforms(
        salesPlatforms,
        restaurantId: effectiveId,
      );
      merged = PlatformCatalog.mergeWithDefaults(saved);
    } on ApiRequestException catch (error) {
      // Production API may not have the dedicated route yet (404).
      if (error.statusCode != 404 && error.statusCode != 405) rethrow;
      await _persist(
        current.copyWith(
          salesPlatforms: mergedLocal,
          updatedAt: DateTime.now().toUtc(),
        ),
        restaurantId: effectiveId,
      );
      return;
    }

    final next = current.copyWith(
      salesPlatforms: merged,
      updatedAt: DateTime.now().toUtc(),
    );
    _setCache(next, effectiveId ?? '');
    await _saveCache(next, effectiveId ?? '');
    await _syncFirebase(next);
    notifyListeners();
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
    required String heroImageUrl,
    required String restaurantDescription,
    String? restaurantId,
  }) async {
    final current = _cached ?? await load(restaurantId: restaurantId);
    await _persist(
      current.copyWith(
        logoUrl: logoUrl.trim(),
        heroImageUrl: heroImageUrl.trim(),
        restaurantDescription: restaurantDescription.trim(),
        updatedAt: DateTime.now().toUtc(),
      ),
      restaurantId: restaurantId,
    );
  }

  Future<void> saveLinkHub({
    required LinkHubConfig linkHub,
    String? restaurantId,
  }) async {
    final scopedRestaurantId = restaurantId ??
        SuperAdminScopeService.instance.effectiveRestaurantId;
    final current = _cached ?? await load(restaurantId: scopedRestaurantId);
    await _persist(
      current.copyWith(
        linkHub: linkHub,
        updatedAt: DateTime.now().toUtc(),
      ),
      restaurantId: scopedRestaurantId,
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

  Future<void> saveDynamicMenuSettings({
    required bool dynamicMenuSortingEnabled,
    required int paydayStartDay,
    String? restaurantId,
  }) async {
    final scopedRestaurantId = restaurantId ??
        SuperAdminScopeService.instance.effectiveRestaurantId;
    final current = _cached ?? await load(restaurantId: scopedRestaurantId);
    await _persist(
      current.copyWith(
        dynamicMenuSortingEnabled: dynamicMenuSortingEnabled,
        paydayStartDay: paydayStartDay,
        updatedAt: DateTime.now().toUtc(),
      ),
      restaurantId: scopedRestaurantId,
    );
  }

  Future<void> clearCache() async {
    final restaurantId = _cachedRestaurantId;
    _cached = null;
    _cachedRestaurantId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey(restaurantId));
    await prefs.remove('restaurant_settings_cache');
    notifyListeners();
  }

  /// Drops cached settings for a tenant after Super Admin subscription changes.
  Future<void> invalidateRestaurant(String restaurantId) async {
    final id = restaurantId.trim();
    if (id.isEmpty) return;
    if (_cachedRestaurantId == id) {
      _cached = null;
      _cachedRestaurantId = null;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey(id));
    notifyListeners();
  }

  void _setCache(RestaurantSettings settings, String restaurantId) {
    _cached = settings;
    _cachedRestaurantId = restaurantId;
    notifyListeners();
  }

  Future<void> _persist(
    RestaurantSettings settings, {
    String? restaurantId,
  }) async {
    final scopedId = (restaurantId ??
            SuperAdminScopeService.instance.effectiveRestaurantId)
        .trim();
    final saved = await ApiService.instance.updateSettings(
      settings,
      restaurantId: scopedId.isEmpty ? restaurantId : scopedId,
    );
    _setCache(saved, scopedId);
    await _saveCache(saved, scopedId);
    await _syncFirebase(saved);
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

  Future<void> _saveCache(
    RestaurantSettings settings,
    String restaurantId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey(restaurantId),
      jsonEncode(settings.toJson()),
    );
  }

  Future<RestaurantSettings?> _loadCache(String restaurantId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey(restaurantId)) ??
        (restaurantId.isEmpty
            ? null
            : prefs.getString('restaurant_settings_cache'));
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
