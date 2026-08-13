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
      defaultValue: 'https://almenupro-backend.vercel.app/api',
    );
    return configured;
  }

  static const Duration _fetchTimeout = Duration(seconds: 15);
  static const Duration _writeTimeout = Duration(seconds: 30);

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        ...AdminAuthService.instance.authHeaders,
      };

  Map<String, String> get _publicHeaders => const {
        'Content-Type': 'application/json',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$baseUrl$path').replace(queryParameters: query);
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

  Future<List<MenuItem>> fetchItems({String? restaurantId}) async {
    try {
      final query = <String, String>{};
      final scopedId = restaurantId ?? AdminAuthService.instance.restaurantId;
      if (scopedId != null && scopedId.isNotEmpty) {
        query['restaurant_id'] = scopedId;
      } else {
        query['restaurant_id'] = defaultRestaurantId;
      }

      final response = await http
          .get(_uri('/items', query), headers: _jsonHeaders)
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

  Future<List<MenuItem>> fetchMenuItems({String? restaurantId}) =>
      fetchItems(restaurantId: restaurantId);

  Future<bool> isOnline() async {
    try {
      final response = await http
          .get(_uri('/health'))
          .timeout(const Duration(seconds: 10));
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

      final response = await http
          .get(_uri('/orders', query.isEmpty ? null : query), headers: _jsonHeaders)
          .timeout(_fetchTimeout);

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
        ..['restaurantId'] = restaurantId;

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
      final query = <String, String>{};
      final scopedId = restaurantId ?? AdminAuthService.instance.restaurantId;
      if (scopedId != null) {
        query['restaurant_id'] = scopedId;
      } else {
        query['restaurant_id'] = defaultRestaurantId;
      }

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
    final response = await http
        .post(
          _uri('/items'),
          headers: _jsonHeaders,
          body: jsonEncode(_itemPayload(data)),
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
    final response = await http
        .delete(_uri('/items/$itemId'), headers: _jsonHeaders)
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في حذف الصنف (${response.statusCode})');
    }
  }

  Future<MenuItem> setMenuItemAvailability(String itemId, bool isAvailable) async {
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

