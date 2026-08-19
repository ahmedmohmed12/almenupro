import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/customer.dart';
import '../models/customer_checkout_profile.dart';
import '../models/delivery_zone.dart';
import '../models/loyalty_cashback.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../models/restaurant.dart';
import '../models/restaurant_settings.dart';
import '../models/upsell_recommendation.dart';
import 'admin_auth_service.dart';
import 'super_admin_scope_service.dart';

class ApiService {
  ApiService._();

  static final ApiService instance = ApiService._();

  factory ApiService() => instance;

  static const String defaultRestaurantId = 'rest_molton';

  static String get baseUrl {
    const configured = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://backend-henna-chi-76.vercel.app/api',
    );
    return configured;
  }

  static const Duration _fetchTimeout = Duration(seconds: 45);
  static const Duration _writeTimeout = Duration(seconds: 60);

  List<MenuItem>? _cachedItems;
  String? _cachedItemsKey;
  DateTime? _cachedItemsAt;

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        ...AdminAuthService.instance.authHeaders,
        ...SuperAdminScopeService.instance.scopeHeaders,
      };

  Map<String, String> get _publicHeaders => const {
        'Content-Type': 'application/json',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$baseUrl$path').replace(queryParameters: query);
  }

  Future<http.Response> _get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final duration = timeout ?? _fetchTimeout;
    final hdrs = headers ?? _jsonHeaders;
    try {
      return await http.get(uri, headers: hdrs).timeout(duration);
    } on TimeoutException {
      return await http.get(uri, headers: hdrs).timeout(duration);
    }
  }

  Future<AdminSession> loginAdmin({
    String? username,
    String? restaurantSlug,
    required String password,
  }) async {
    final payload = <String, dynamic>{
      'password': password,
    };

    if (username != null && username.trim().isNotEmpty) {
      payload['username'] = username.trim();
    } else if (restaurantSlug != null && restaurantSlug.trim().isNotEmpty) {
      payload['restaurantSlug'] = restaurantSlug.trim();
    } else {
      throw Exception('يرجى إدخال اسم المستخدم أو معرف المطعم');
    }

    final response = await http
        .post(
          _uri('/auth/login'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('بيانات الدخول غير صحيحة');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return AdminSession.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<List<Restaurant>> fetchRestaurants() async {
    final response = await http
        .get(_uri('/restaurants'), headers: _jsonHeaders)
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في تحميل المطاعم (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return decoded
        .whereType<Map>()
        .map((entry) => Restaurant.fromJson(Map<String, dynamic>.from(entry)))
        .toList();
  }

  Future<List<Restaurant>> fetchPublicRestaurants() async {
    final response = await http
        .get(_uri('/public/restaurants'), headers: _publicHeaders)
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في تحميل المطاعم (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return decoded
        .whereType<Map>()
        .map((entry) => Restaurant.fromJson(Map<String, dynamic>.from(entry)))
        .where((entry) => entry.isActive)
        .toList();
  }

  Future<Restaurant> fetchPublicRestaurant({
    String? slug,
    String? restaurantId,
  }) async {
    final cleanSlug = slug?.trim().toLowerCase();
    final path = (cleanSlug != null && cleanSlug.isNotEmpty)
        ? '/public/restaurants/${Uri.encodeComponent(cleanSlug)}'
        : '/public/restaurants';
    final query = (cleanSlug == null || cleanSlug.isEmpty)
        ? _publicRestaurantQuery(restaurantId: restaurantId)
        : null;
    final response = await http
        .get(_uri(path, query), headers: _publicHeaders)
        .timeout(_fetchTimeout);

    if (response.statusCode == 404) {
      throw Exception('المطعم غير موجود');
    }
    if (response.statusCode != 200) {
      throw Exception('فشل في تحميل المطعم (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      final restaurants = decoded
          .whereType<Map>()
          .map((entry) => Restaurant.fromJson(Map<String, dynamic>.from(entry)))
          .toList();
      if (restaurants.isEmpty) {
        throw Exception('المطعم غير موجود');
      }
      return restaurants.first;
    }
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    return Restaurant.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<Restaurant> createRestaurant({
    required String name,
    required String slug,
    required String adminPassword,
    String ownerName = '',
    String phone = '',
    RestaurantStatus status = RestaurantStatus.active,
    SubscriptionPlan subscriptionPlan = SubscriptionPlan.free,
    SubscriptionStatus subscriptionStatus = SubscriptionStatus.active,
    DateTime? subscriptionExpiresAt,
    String subscriptionNotes = '',
  }) async {
    final response = await http
        .post(
          _uri('/restaurants'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'name': name,
            'slug': slug,
            'adminPassword': adminPassword,
            if (ownerName.isNotEmpty) 'ownerName': ownerName,
            if (phone.isNotEmpty) 'phone': phone,
            'status': status.apiValue,
            'subscriptionPlan': subscriptionPlan.apiValue,
            'subscriptionStatus': subscriptionStatus.apiValue,
            if (subscriptionExpiresAt != null)
              'subscriptionExpiresAt':
                  subscriptionExpiresAt.toUtc().toIso8601String(),
            if (subscriptionNotes.isNotEmpty) 'subscriptionNotes': subscriptionNotes,
          }),
        )
        .timeout(_fetchTimeout);

    if (response.statusCode != 201 && response.statusCode != 200) {
      final body = response.body;
      throw Exception('فشل في إنشاء المطعم (${response.statusCode}) $body');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return Restaurant.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<List<MenuItem>> fetchItems({
    String? restaurantId,
    int? limit,
    int? offset,
    bool lite = false,
  }) async {
    final page = await fetchItemsPage(
      restaurantId: restaurantId,
      limit: limit,
      offset: offset,
      lite: lite,
    );
    return page.items;
  }

  Future<({List<MenuItem> items, int total})> fetchItemsPage({
    String? restaurantId,
    int? limit,
    int? offset,
    bool lite = false,
  }) async {
    try {
      final query = <String, String>{};
      final scopedId = _scopedRestaurantId(restaurantId: restaurantId);
      query['restaurant_id'] = scopedId;
      if (lite) query['lite'] = '1';
      query['limit'] = '${limit != null && limit > 0 ? limit : 40}';
      if (offset != null && offset > 0) query['offset'] = '$offset';

      final cacheKey = query.entries.map((e) => '${e.key}=${e.value}').join('&');
      final cacheFresh = _cachedItems != null &&
          _cachedItemsKey == cacheKey &&
          _cachedItemsAt != null &&
          DateTime.now().difference(_cachedItemsAt!) < const Duration(seconds: 45);
      if (cacheFresh) {
        return (items: _cachedItems!, total: _cachedItems!.length);
      }

      final response = await _get(_uri('/items', query), headers: _jsonHeaders);

      if (response.statusCode != 200) {
        throw Exception('فشل في تحميل الأصناف (${response.statusCode})');
      }

      final decoded = (!kIsWeb && response.body.length > 40000)
          ? await compute(jsonDecode, response.body)
          : jsonDecode(response.body);
      final List<dynamic> rawList;
      var total = 0;
      if (decoded is List) {
        rawList = decoded;
        total = int.tryParse(response.headers['x-total-count'] ?? '') ??
            rawList.length;
      } else if (decoded is Map) {
        final nested = decoded['items'] ?? decoded['data'] ?? decoded['results'];
        if (nested is List) {
          rawList = nested;
          total = (decoded['total'] as num?)?.toInt() ??
              int.tryParse(response.headers['x-total-count'] ?? '') ??
              rawList.length;
        } else {
          rawList = const [];
          total = 0;
        }
      } else {
        rawList = const [];
        total = 0;
      }

      final items = rawList
          .whereType<Map>()
          .map((item) {
            try {
              return MenuItem.fromJson(Map<String, dynamic>.from(item));
            } catch (_) {
              return null;
            }
          })
          .whereType<MenuItem>()
          .where((item) => item.name.trim().isNotEmpty)
          .toList();
      total = total < items.length ? items.length : total;

      if (limit == null || limit >= 40) {
        // Only cache the first page of a default-sized request.
        if ((offset ?? 0) == 0) {
          _cachedItems = items;
          _cachedItemsKey = cacheKey;
          _cachedItemsAt = DateTime.now();
        }
      }

      return (items: items, total: total);
    } on TimeoutException {
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } on FormatException {
      throw Exception('تعذر قراءة بيانات المنيو من السيرفر');
    } catch (error) {
      if (error is Exception && error.toString().contains('فشل')) rethrow;
      if (error is Exception && error.toString().contains('انتهت')) rethrow;
      if (error is Exception && error.toString().contains('تعذر')) rethrow;
      throw Exception('خطأ في الاتصال بالسيرفر: $error');
    }
  }

  void invalidateItemsCache() {
    _cachedItems = null;
    _cachedItemsKey = null;
    _cachedItemsAt = null;
  }

  Future<List<MenuItem>> fetchMenuItems({
    String? restaurantId,
    int? limit,
    int? offset,
    bool lite = false,
  }) =>
      fetchItems(
        restaurantId: restaurantId,
        limit: limit,
        offset: offset,
        lite: lite,
      );

  Future<bool> isOnline() async {
    try {
      final response = await _get(
        _uri('/health'),
        timeout: const Duration(seconds: 20),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<Order>> fetchOrders() async {
    try {
      final query = <String, String>{};
      final restaurantId = AdminAuthService.instance.restaurantId;
      if (restaurantId != null) {
        query['restaurant_id'] = restaurantId;
      }

      final response = await _get(
        _uri('/orders', query.isEmpty ? null : query),
        headers: _jsonHeaders,
      );

      if (response.statusCode != 200) {
        throw Exception('فشل في تحميل الطلبات (${response.statusCode})');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw Exception('استجابة غير متوقعة من السيرفر');
      }

      return decoded
          .whereType<Map>()
          .map(
            (raw) => Order.fromMap(
              raw['id']?.toString() ?? '',
              Map<String, dynamic>.from(raw),
            ),
          )
          .toList();
    } on TimeoutException {
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } catch (error) {
      throw Exception('خطأ في تحميل الطلبات: $error');
    }
  }

  Future<Order> createOrder(
    Order order, {
    String restaurantId = defaultRestaurantId,
  }) async {
    try {
      final payload = order.toMap()
        ..['restaurantId'] = restaurantId
        ..['restaurant_id'] = restaurantId;

      final response = await http
          .post(
            _uri('/orders'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(_fetchTimeout);

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('فشل في حفظ الطلب (${response.statusCode})');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw Exception('استجابة غير متوقعة من السيرفر');
      }

      final map = Map<String, dynamic>.from(decoded);
      return Order.fromMap(map['id']?.toString() ?? '', map);
    } on TimeoutException {
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } catch (error) {
      throw Exception('خطأ في حفظ الطلب: $error');
    }
  }

  Future<RestaurantSettings> fetchSettings({String? restaurantId}) async {
    try {
      final query = _restaurantQuery(restaurantId: restaurantId);

      final response = await http
          .get(_uri('/settings', query), headers: _jsonHeaders)
          .timeout(_fetchTimeout);

      if (response.statusCode != 200) {
        throw Exception('فشل في تحميل الإعدادات (${response.statusCode})');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw Exception('استجابة غير متوقعة من السيرفر');
      }

      return RestaurantSettings.fromJson(Map<String, dynamic>.from(decoded));
    } on TimeoutException {
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } catch (error) {
      throw Exception('خطأ في تحميل الإعدادات: $error');
    }
  }

  Future<RestaurantSettings> updateSettings(
    RestaurantSettings settings, {
    String? restaurantId,
  }) async {
    try {
      final payload = settings.copyWith(updatedAt: DateTime.now().toUtc());
      final body = payload.toJson();
      final scopedId = restaurantId ??
          SuperAdminScopeService.instance.effectiveRestaurantId;
      if (scopedId.isNotEmpty) {
        body['restaurantId'] = scopedId;
      }

      final response = await http
          .put(
            _uri('/settings'),
            headers: _jsonHeaders,
            body: jsonEncode(body),
          )
          .timeout(_fetchTimeout);

      if (response.statusCode != 200) {
        throw Exception('فشل في حفظ الإعدادات (${response.statusCode})');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return payload;
      }

      return RestaurantSettings.fromJson(Map<String, dynamic>.from(decoded));
    } on TimeoutException {
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } catch (error) {
      throw Exception('خطأ في حفظ الإعدادات: $error');
    }
  }

  Future<void> updateOrderStatus(
    String orderId,
    OrderStatus status, {
    String? shiftId,
    String? cashierId,
  }) async {
    try {
      final response = await http
          .patch(
            _uri('/orders/$orderId/status'),
            headers: _jsonHeaders,
            body: jsonEncode({
              'status': status.name,
              if (shiftId != null && shiftId.isNotEmpty) 'shiftId': shiftId,
              if (cashierId != null && cashierId.isNotEmpty) 'cashierId': cashierId,
            }),
          )
          .timeout(_fetchTimeout);

      if (response.statusCode != 200) {
        throw Exception('فشل في تحديث الطلب (${response.statusCode})');
      }
    } on TimeoutException {
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } catch (error) {
      throw Exception('خطأ في تحديث الطلب: $error');
    }
  }

  Future<bool> syncMenuItems(
    List<Map<String, dynamic>> items, {
    required String restaurantId,
  }) async {
    if (items.isEmpty) return true;

    try {
      final response = await http
          .post(
            _uri('/items/sync'),
            headers: _jsonHeaders,
            body: jsonEncode({
              'items': items,
              'restaurantId': restaurantId,
              'downloadImages': true,
            }),
          )
          .timeout(const Duration(seconds: 120));

      return response.statusCode == 200;
    } catch (error) {
      debugPrint('ApiService syncMenuItems failed: $error');
      return false;
    }
  }

  Future<MenuItem> createMenuItem(Map<String, dynamic> data) async {
    invalidateItemsCache();
    final restaurantId = _scopedRestaurantId();
    final response = await http
        .post(
          _uri('/items'),
          headers: _jsonHeaders,
          body: jsonEncode({
            ..._itemPayload(data),
            'restaurant_id': restaurantId,
            'restaurantId': restaurantId,
          }),
        )
        .timeout(_fetchTimeout);

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('فشل في إضافة الصنف (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return MenuItem.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<MenuItem> updateMenuItem(String itemId, Map<String, dynamic> data) async {
    invalidateItemsCache();
    final response = await http
        .put(
          _uri('/items/$itemId'),
          headers: _jsonHeaders,
          body: jsonEncode(_itemPayload(data)),
        )
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في تحديث الصنف (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return MenuItem.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<void> deleteMenuItem(String itemId) async {
    invalidateItemsCache();
    final response = await http
        .delete(_uri('/items/$itemId'), headers: _jsonHeaders)
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في حذف الصنف (${response.statusCode})');
    }
  }

  Future<MenuItem> setMenuItemAvailability(String itemId, bool isAvailable) async {
    invalidateItemsCache();
    final response = await http
        .patch(
          _uri('/items/$itemId/availability'),
          headers: _jsonHeaders,
          body: jsonEncode({'isAvailable': isAvailable}),
        )
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في تحديث حالة الصنف (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return MenuItem.fromJson(Map<String, dynamic>.from(decoded));
  }

  Map<String, dynamic> _itemPayload(Map<String, dynamic> data) {
    return {
      'name': data['name'],
      'description': data['description'] ?? '',
      'price': data['price'] ?? 0,
      'categoryName': data['categoryName'] ?? data['category_name'] ?? 'عام',
      'imageUrl': data['imageUrl'] ?? data['image_url'] ?? '',
      'isAvailable': data['isAvailable'] ?? data['is_available'] ?? true,
      'source': data['source'] ?? 'Manual',
    };
  }

  String _scopedRestaurantId({String? restaurantId}) {
    if (restaurantId != null && restaurantId.isNotEmpty) {
      return restaurantId;
    }
    final scoped = SuperAdminScopeService.instance.effectiveRestaurantId;
    if (scoped.isNotEmpty) return scoped;
    return AdminAuthService.instance.restaurantId ??
        defaultRestaurantId;
  }

  Map<String, String> _restaurantQuery({String? restaurantId}) {
    final scoped = _scopedRestaurantId(restaurantId: restaurantId);
    return {
      'restaurant_id': scoped,
      'restaurantId': scoped,
    };
  }

  Map<String, String> _publicRestaurantQuery({
    String? slug,
    String? restaurantId,
  }) {
    final cleanSlug = slug?.trim();
    if (cleanSlug != null && cleanSlug.isNotEmpty) {
      return {'slug': cleanSlug};
    }
    final scoped = _scopedRestaurantId(restaurantId: restaurantId);
    return {
      'restaurant_id': scoped,
      'restaurantId': scoped,
    };
  }

  Future<List<MenuItem>> fetchPublicItems({
    String? restaurantId,
    String? slug,
  }) async {
    try {
      final query = _publicRestaurantQuery(
        restaurantId: restaurantId,
        slug: slug,
      );
      final response = await http
          .get(_uri('/items', query), headers: _publicHeaders)
          .timeout(_fetchTimeout);

      if (response.statusCode != 200) {
        throw Exception('فشل في تحميل الأصناف (${response.statusCode})');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw Exception('استجابة غير متوقعة من السيرفر');
      }

      return decoded
          .whereType<Map>()
          .map((item) => MenuItem.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.name.trim().isNotEmpty)
          .toList();
    } on TimeoutException {
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } on FormatException {
      throw Exception('تعذر قراءة بيانات المنيو من السيرفر');
    } catch (error) {
      throw Exception('خطأ في الاتصال بالسيرفر: $error');
    }
  }

  Future<List<int>> fetchTopMenuItemIds({
    String? restaurantId,
    int limit = 12,
    int days = 90,
  }) async {
    try {
      final query = {
        ..._publicRestaurantQuery(restaurantId: restaurantId),
        'limit': '$limit',
        'days': '$days',
      };
      final response = await http
          .get(_uri('/analytics/top-items', query), headers: _publicHeaders)
          .timeout(_fetchTimeout);

      if (response.statusCode != 200) {
        throw Exception('فشل في تحميل الأصناف المميزة (${response.statusCode})');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return const [];
      }

      return decoded
          .map((id) => int.tryParse(id.toString()))
          .whereType<int>()
          .toList();
    } catch (error) {
      debugPrint('fetchTopMenuItemIds failed: $error');
      return const [];
    }
  }

  Future<StorageHealth> fetchStorageHealth() async {
    final response = await http
        .get(_uri('/health'), headers: _publicHeaders)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('فشل في فحص السيرفر (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return StorageHealth.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<Restaurant> updateRestaurant({
    required String id,
    required String name,
    required String slug,
    String ownerName = '',
    String phone = '',
    RestaurantStatus status = RestaurantStatus.active,
    SubscriptionPlan subscriptionPlan = SubscriptionPlan.free,
    SubscriptionStatus subscriptionStatus = SubscriptionStatus.active,
    DateTime? subscriptionExpiresAt,
    String subscriptionNotes = '',
    String? adminPassword,
  }) async {
    final response = await http
        .patch(
          _uri('/restaurants/$id'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'name': name,
            'slug': slug,
            if (ownerName.isNotEmpty) 'ownerName': ownerName,
            if (phone.isNotEmpty) 'phone': phone,
            'status': status.apiValue,
            'subscriptionPlan': subscriptionPlan.apiValue,
            'subscriptionStatus': subscriptionStatus.apiValue,
            if (subscriptionExpiresAt != null)
              'subscriptionExpiresAt': subscriptionExpiresAt.toUtc().toIso8601String(),
            if (subscriptionNotes.isNotEmpty) 'subscriptionNotes': subscriptionNotes,
            if (adminPassword != null && adminPassword.isNotEmpty)
              'adminPassword': adminPassword,
          }),
        )
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      String message = 'فشل في تحديث المطعم (${response.statusCode})';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] != null) {
          message = decoded['error'].toString();
        }
      } catch (_) {}
      throw Exception(message);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return Restaurant.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<TalabatImportResult> importTalabatMenu({
    required String url,
    required String restaurantId,
  }) async {
    try {
      final response = await http
          .post(
            _uri('/talabat/import'),
            headers: _jsonHeaders,
            body: jsonEncode({
              'url': url,
              'restaurantId': restaurantId,
              'downloadImages': true,
            }),
          )
          .timeout(const Duration(seconds: 180));

      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200) {
        final message = decoded is Map
            ? decoded['error']?.toString() ?? 'فشل استيراد المنيو'
            : 'فشل استيراد المنيو (${response.statusCode})';
        throw Exception(message);
      }

      if (decoded is! Map) {
        throw Exception('استجابة غير متوقعة من السيرفر');
      }

      return TalabatImportResult.fromJson(Map<String, dynamic>.from(decoded));
    } on TimeoutException {
      throw Exception('انتهت مهلة الاستيراد — حاول مرة أخرى');
    } catch (error) {
      if (error is Exception) rethrow;
      throw Exception('خطأ في استيراد المنيو: $error');
    }
  }

  Future<List<DeliveryZone>> fetchDeliveryZones({
    String? restaurantId,
    String? slug,
  }) async {
    final query = slug != null && slug.trim().isNotEmpty
        ? _publicRestaurantQuery(slug: slug, restaurantId: restaurantId)
        : _restaurantQuery(restaurantId: restaurantId);

    final headers = AdminAuthService.instance.isLoggedIn
        ? _jsonHeaders
        : _publicHeaders;

    final response = await http
        .get(_uri('/delivery-zones', query), headers: headers)
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في تحميل مناطق التوصيل (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];

    return decoded
        .whereType<Map>()
        .map((raw) => DeliveryZone.fromMap(Map<String, dynamic>.from(raw)))
        .where((zone) => zone.isActive)
        .toList();
  }

  Future<DeliveryZone> createDeliveryZone(DeliveryZone zone) async {
    final scoped = _scopedRestaurantId(restaurantId: zone.restaurantId);
    final payload = zone.toMap()
      ..['restaurantId'] = scoped
      ..['restaurant_id'] = scoped
      ..['area_name'] = zone.areaName
      ..['delivery_fee'] = zone.deliveryFee;
    if (zone.defaultKitchenId != null && zone.defaultKitchenId!.isNotEmpty) {
      payload['defaultKitchenId'] = zone.defaultKitchenId;
      payload['default_kitchen_id'] = zone.defaultKitchenId;
    }

    final response = await http
        .post(
          _uri('/delivery-zones'),
          headers: _jsonHeaders,
          body: jsonEncode(payload),
        )
        .timeout(_writeTimeout);

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('فشل في إضافة منطقة التوصيل (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return DeliveryZone.fromMap(Map<String, dynamic>.from(decoded));
  }

  Future<DeliveryZone> updateDeliveryZone(DeliveryZone zone) async {
    final payload = zone.toMap()
      ..['area_name'] = zone.areaName
      ..['delivery_fee'] = zone.deliveryFee;
    if (zone.defaultKitchenId != null && zone.defaultKitchenId!.isNotEmpty) {
      payload['defaultKitchenId'] = zone.defaultKitchenId;
      payload['default_kitchen_id'] = zone.defaultKitchenId;
    }

    final response = await http
        .put(
          _uri('/delivery-zones/${zone.id}'),
          headers: _jsonHeaders,
          body: jsonEncode(payload),
        )
        .timeout(_writeTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في تحديث منطقة التوصيل (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return DeliveryZone.fromMap(Map<String, dynamic>.from(decoded));
  }

  Future<void> deleteDeliveryZone(String zoneId) async {
    final response = await http
        .delete(_uri('/delivery-zones/$zoneId'), headers: _jsonHeaders)
        .timeout(_writeTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في حذف منطقة التوصيل (${response.statusCode})');
    }
  }

  Future<List<Customer>> fetchCustomers({String? restaurantId}) async {
    final query = <String, String>{};
    if (restaurantId != null && restaurantId.trim().isNotEmpty) {
      query['restaurant_id'] = restaurantId.trim();
    } else if (AdminAuthService.instance.restaurantId != null) {
      query['restaurant_id'] = AdminAuthService.instance.restaurantId!;
    }

    final response = await http
        .get(_uri('/customers', query.isEmpty ? null : query), headers: _jsonHeaders)
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في تحميل العملاء (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];

    return decoded
        .whereType<Map>()
        .map((raw) => Customer.fromMap(Map<String, dynamic>.from(raw)))
        .toList();
  }

  Future<CustomerDetailData> fetchCustomerDetail(
    String customerId, {
    String? restaurantId,
  }) async {
    final query = <String, String>{};
    if (restaurantId != null && restaurantId.trim().isNotEmpty) {
      query['restaurant_id'] = restaurantId.trim();
    } else if (AdminAuthService.instance.restaurantId != null) {
      query['restaurant_id'] = AdminAuthService.instance.restaurantId!;
    }

    final response = await http
        .get(
          _uri('/customers/$customerId', query.isEmpty ? null : query),
          headers: _jsonHeaders,
        )
        .timeout(_fetchTimeout);

    if (response.statusCode == 404) {
      throw Exception('العميل غير موجود');
    }
    if (response.statusCode != 200) {
      throw Exception('فشل في تحميل بيانات العميل (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return CustomerDetailData.fromMap(Map<String, dynamic>.from(decoded));
  }

  Future<CustomerCheckoutProfile?> fetchCustomerCheckoutProfile({
    required String phone,
    String? restaurantId,
  }) async {
    final normalizedPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (normalizedPhone.length < 8) return null;

    final query = <String, String>{'phone': normalizedPhone};
    query['restaurantId'] = _scopedRestaurantId(restaurantId: restaurantId);

    try {
      final response = await http
          .get(_uri('/customers/lookup', query), headers: _publicHeaders)
          .timeout(_fetchTimeout);

      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;

      final profileRaw = decoded['profile'];
      if (profileRaw is! Map) return null;

      final profile = CustomerCheckoutProfile.fromMap(
        Map<String, dynamic>.from(profileRaw),
      );
      if (profile.hasUsableData ||
          profile.hasActivePromo ||
          profile.hasWalletBalance) {
        return profile;
      }
      return null;
    } catch (error) {
      debugPrint('Customer lookup failed: $error');
      return null;
    }
  }

  Future<Map<String, dynamic>> identifyCustomer({
    required String phone,
    String? restaurantId,
  }) async {
    final response = await http
        .post(
          _uri('/customers/identify'),
          headers: _publicHeaders,
          body: jsonEncode({
            'phone': phone,
            'restaurantId': _scopedRestaurantId(restaurantId: restaurantId),
          }),
        )
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('تعذر التحقق من رقم الهاتف');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<Map<String, dynamic>> fetchDailySalesAnalytics({
    String? restaurantId,
    int days = 1,
  }) async {
    return _getJsonMap(
      '/analytics/daily-sales',
      query: {
        ..._restaurantQuery(restaurantId: restaurantId),
        'days': '$days',
      },
    );
  }

  Future<Map<String, dynamic>> fetchFoodCostReport({
    String? restaurantId,
    int days = 30,
  }) async {
    return _getJsonMap(
      '/analytics/food-cost',
      query: {
        ..._restaurantQuery(restaurantId: restaurantId),
        'days': '$days',
      },
    );
  }

  Future<Map<String, dynamic>> fetchUpsellAnalytics({
    String? restaurantId,
    int days = 30,
  }) async {
    return _getJsonMap(
      '/analytics/upsell',
      query: {
        ..._restaurantQuery(restaurantId: restaurantId),
        'days': '$days',
      },
    );
  }

  Future<void> logUpsellEvents({
    required List<Map<String, dynamic>> events,
    String? slug,
    String? restaurantId,
  }) async {
    if (events.isEmpty) return;
    try {
      await http
          .post(
            _uri('/analytics/upsell-events'),
            headers: _publicHeaders,
            body: jsonEncode({
              'events': events,
              if (slug != null && slug.isNotEmpty) 'slug': slug,
              'restaurantId': _scopedRestaurantId(restaurantId: restaurantId),
            }),
          )
          .timeout(_writeTimeout);
    } catch (error) {
      debugPrint('logUpsellEvents failed: $error');
    }
  }

  Future<LoyaltyCashbackPreview> calculateLoyaltyCashback({
    required double orderTotal,
    String? restaurantId,
  }) async {
    final map = await _getJsonMap(
      '/loyalty/cashback',
      query: {
        ..._restaurantQuery(restaurantId: restaurantId),
        'orderTotal': '$orderTotal',
      },
    );
    return LoyaltyCashbackPreview.fromMap(map);
  }

  Future<List<UpsellRecommendation>> fetchSmartUpsell({
    required List<Map<String, dynamic>> cartItems,
    double? cartTotal,
    String? restaurantId,
  }) async {
    if (cartItems.isEmpty) return const [];

    final response = await http
        .post(
          _uri('/pos/smart-upsell'),
          headers: {
            ..._jsonHeaders,
            'X-Restaurant-Id': _scopedRestaurantId(restaurantId: restaurantId),
          },
          body: jsonEncode({
            'cartItems': cartItems,
            'cartTotal': ?cartTotal,
            'restaurantId': _scopedRestaurantId(restaurantId: restaurantId),
          }),
        )
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('تعذر تحميل توصيات البياع الشاطر (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return const [];

    final suggested = decoded['suggestedItems'] ?? decoded['suggested_items'];
    if (suggested is! List) return const [];

    return suggested.whereType<Map>().map((entry) {
      final map = Map<String, dynamic>.from(entry);
      final id = map['id']?.toString() ?? map['menuItemId']?.toString() ?? '';
      return UpsellRecommendation.fromJson(
        map,
        MenuItem.fromMap(id, map),
      );
    }).toList();
  }

  Future<Map<String, dynamic>> _getJsonMap(
    String path, {
    Map<String, String>? query,
  }) async {
    final response = await http
        .get(_uri(path, query), headers: _jsonHeaders)
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في تحميل البيانات (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    return Map<String, dynamic>.from(decoded);
  }
}

class TalabatImportResult {
  const TalabatImportResult({
    required this.added,
    required this.updated,
    required this.skipped,
    required this.synced,
    required this.total,
    this.menuUrl,
  });

  final int added;
  final int updated;
  final int skipped;
  final int synced;
  final int total;
  final String? menuUrl;

  factory TalabatImportResult.fromJson(Map<String, dynamic> json) {
    return TalabatImportResult(
      added: _toInt(json['added']),
      updated: _toInt(json['updated']),
      skipped: _toInt(json['skipped']),
      synced: _toInt(json['synced']),
      total: _toInt(json['total']),
      menuUrl: json['menuUrl']?.toString(),
    );
  }

  static int _toInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class StorageHealth {
  const StorageHealth({
    required this.ok,
    required this.storage,
    required this.persistent,
    this.message,
  });

  final bool ok;
  final String storage;
  final bool persistent;
  final String? message;

  factory StorageHealth.fromJson(Map<String, dynamic> json) {
    return StorageHealth(
      ok: json['ok'] == true,
      storage: json['storage']?.toString() ?? 'unknown',
      persistent: json['persistent'] == true,
      message: json['persistenceMessage']?.toString(),
    );
  }
}

