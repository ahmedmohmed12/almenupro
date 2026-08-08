import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/restaurant_settings.dart';
import '../models/working_hours.dart';
import '../utils/firebase_config.dart';
import 'api_service.dart';

const _cacheKey = 'restaurant_settings_cache';

class RestaurantSettingsService {
  RestaurantSettingsService._();

  static final RestaurantSettingsService instance = RestaurantSettingsService._();

  RestaurantSettings? _cached;

  RestaurantSettings? get cached => _cached;

  Future<RestaurantSettings> load() async {
    try {
      final remote = await ApiService.instance.fetchSettings();
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
    final updated = current.copyWith(
      workingHours: workingHours,
      updatedAt: DateTime.now().toUtc(),
    );

    await ApiService.instance.updateSettings(updated);
    _cached = updated;
    await _saveCache(updated);
    await _syncFirebase(updated);
  }

  Future<void> saveWhatsappNumber(String whatsappNumber) async {
    final current = _cached ?? await load();
    final updated = current.copyWith(
      whatsappNumber: whatsappNumber.trim(),
      updatedAt: DateTime.now().toUtc(),
    );

    await ApiService.instance.updateSettings(updated);
    _cached = updated;
    await _saveCache(updated);
    await _syncFirebase(updated);
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
