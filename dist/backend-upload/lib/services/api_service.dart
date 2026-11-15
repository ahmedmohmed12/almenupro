import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/customer.dart';
import '../models/customer_checkout_profile.dart';
import '../models/delivery_dispatch.dart';
import '../models/delivery_zone.dart';
import '../models/expense.dart';
import '../models/kitchen.dart';
import '../models/loyalty_cashback.dart';
import '../models/offer.dart';
import '../models/menu_item.dart';
import '../models/menu_category.dart';
import '../models/marketplace_restaurant.dart';
import '../models/order.dart';
import '../models/order_rating_page.dart';
import '../models/restaurant.dart';
import '../models/restaurant_review.dart';
import '../models/restaurant_settings.dart';
import '../models/signup_request.dart';
import '../models/staff_user.dart';
import '../models/upsell_recommendation.dart';
import 'admin_auth_service.dart';
import 'super_admin_scope_service.dart';

class ApiRequestException implements Exception {
  const ApiRequestException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  bool get isOfferUsageLimit => code == 'OFFER_USAGE_LIMIT';

  @override
  String toString() => message;
}

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
  static const Duration _statusTimeout = Duration(seconds: 18);
  static const Duration _writeTimeout = Duration(seconds: 60);

  List<MenuItem>? _cachedItems;
  int _cachedItemsTotal = 0;
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

  ApiRequestException _exceptionFromResponse(
    http.Response response,
    String fallback,
  ) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final message = decoded['error']?.toString().trim() ?? '';
        final code = decoded['code']?.toString();
        if (message.isNotEmpty) {
          return ApiRequestException(
            message,
            code: code,
            statusCode: response.statusCode,
          );
        }
      }
    } catch (_) {}
    return ApiRequestException(fallback, statusCode: response.statusCode);
  }

  Future<bool> isOfferUsableForCustomer({
    required String offerId,
    required String phone,
    String? restaurantId,
  }) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (offerId.isEmpty || digits.length < 8) return true;
    try {
      final query = {
        ..._restaurantQuery(restaurantId: restaurantId),
        'offer_id': offerId,
        'phone': digits,
      };
      final response = await http
          .get(_uri('/offers/check-usage', query), headers: _publicHeaders)
          .timeout(_fetchTimeout);
      if (response.statusCode == 409) return false;
      if (response.statusCode != 200) return true;
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['allowed'] == false) return false;
      return true;
    } catch (_) {
      return true;
    }
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

  Future<({AdminSession session, PosCashierSession cashierSession})> loginCashier({
    required String restaurantName,
    required String cashierName,
    required String pin,
  }) async {
    final response = await http
        .post(
          _uri('/auth/cashier-login'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'restaurantName': restaurantName.trim(),
            'restaurantSlug': restaurantName.trim(),
            'cashierName': cashierName.trim(),
            'pin': pin.trim(),
            'password': pin.trim(),
          }),
        )
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('بيانات الكاشير أو المطبخ غير صحيحة');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    final map = Map<String, dynamic>.from(decoded);
    return (
      session: AdminSession.fromJson(map),
      cashierSession: PosCashierSession.fromJson(map),
    );
  }

  Future<AdminSession> loginDriver({
    required String phone,
    required String pin,
  }) async {
    final response = await http
        .post(
          _uri('/auth/driver-login'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'phone': phone.trim(),
            'pin': pin.trim(),
            'password': pin.trim(),
          }),
        )
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'رقم الهاتف أو رمز PIN غير صحيح');
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

  Future<MarketplaceCatalog> fetchMarketplaceCatalog() async {
    final response = await http
        .get(_uri('/public/marketplace'), headers: _publicHeaders)
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في تحميل الماركت (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return MarketplaceCatalog.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<Restaurant> fetchPublicRestaurant({
    String? slug,
    String? restaurantId,
  }) async {
    final cleanSlug = slug?.trim().toLowerCase();
    final cleanId = restaurantId?.trim() ?? '';
    final pathKey = (cleanSlug != null && cleanSlug.isNotEmpty)
        ? cleanSlug
        : (cleanId.isNotEmpty ? cleanId : null);
    final path = pathKey != null
        ? '/public/restaurants/${Uri.encodeComponent(pathKey)}'
        : '/public/restaurants';
    final query = pathKey == null
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
      if (cleanId.isNotEmpty) {
        final byId = restaurants.where((r) => r.id == cleanId).toList();
        if (byId.isNotEmpty) return byId.first;
      }
      if (cleanSlug != null && cleanSlug.isNotEmpty) {
        final bySlug =
            restaurants.where((r) => r.slug.toLowerCase() == cleanSlug).toList();
        if (bySlug.isNotEmpty) return bySlug.first;
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
    bool tableManagementEnabled = false,
    bool kitchenManagementEnabled = false,
    bool deliveryManagementEnabled = false,
    GeoPointLite? location,
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
            'tableManagement': tableManagementEnabled,
            'kitchenManagement': kitchenManagementEnabled,
            'deliveryManagement': deliveryManagementEnabled,
            if (location != null) 'location': location.toMap(),
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

  Future<String> fetchSignupNotificationEmail() async {
    final response = await http
        .get(_uri('/platform-settings'), headers: _jsonHeaders)
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر تحميل بريد الإشعارات');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return '';
    return decoded['signupNotificationEmail']?.toString() ?? '';
  }

  Future<String> saveSignupNotificationEmail(String email) async {
    final response = await http
        .patch(
          _uri('/platform-settings'),
          headers: _jsonHeaders,
          body: jsonEncode({'signupNotificationEmail': email.trim()}),
        )
        .timeout(_writeTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر حفظ بريد الإشعارات');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return email.trim();
    return decoded['signupNotificationEmail']?.toString() ?? email.trim();
  }

  Future<({List<SignupRequest> requests, int pendingCount})>
      fetchSignupRequests() async {
    final response = await http
        .get(_uri('/signup-requests'), headers: _jsonHeaders)
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر تحميل طلبات الاشتراك');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    final raw = decoded['requests'];
    final list = raw is List
        ? raw
            .whereType<Map>()
            .map((row) => SignupRequest.fromJson(Map<String, dynamic>.from(row)))
            .toList()
        : <SignupRequest>[];
    final pending = decoded['pendingCount'];
    return (
      requests: list,
      pendingCount: pending is num
          ? pending.toInt()
          : list.where((row) => row.isNew).length,
    );
  }

  Future<SignupRequest> updateSignupRequestStatus({
    required String id,
    required String status,
  }) async {
    final response = await http
        .patch(
          _uri('/signup-requests/$id'),
          headers: _jsonHeaders,
          body: jsonEncode({'status': status}),
        )
        .timeout(_writeTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر تحديث الطلب');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    return SignupRequest.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<SignupRequest> markSignupEmailSent(String id) async {
    final response = await http
        .patch(
          _uri('/signup-requests/$id'),
          headers: _jsonHeaders,
          body: jsonEncode({'markEmailSent': true}),
        )
        .timeout(_writeTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر تحديث حالة الإيميل');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    return SignupRequest.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<SignupRequest> resendSignupRequestEmail(String id) async {
    final response = await http
        .patch(
          _uri('/signup-requests/$id'),
          headers: _jsonHeaders,
          body: jsonEncode({'resendEmail': true}),
        )
        .timeout(_writeTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر إعادة إرسال الإيميل');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    return SignupRequest.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<List<MenuItem>> fetchItems({
    String? restaurantId,
    int? limit,
    int? offset,
    bool lite = false,
    String? channel,
  }) async {
    final page = await fetchItemsPage(
      restaurantId: restaurantId,
      limit: limit,
      offset: offset,
      lite: lite,
      channel: channel,
    );
    return page.items;
  }

  Future<({List<MenuItem> items, int total})> fetchItemsPage({
    String? restaurantId,
    int? limit,
    int? offset,
    bool lite = false,
    String? channel,
  }) async {
    try {
      final query = <String, String>{};
      final scopedId = _scopedRestaurantId(restaurantId: restaurantId);
      query['restaurant_id'] = scopedId;
      if (lite) query['lite'] = '1';
      if (channel != null && channel.trim().isNotEmpty) {
        query['channel'] = channel.trim();
      }
      query['limit'] = '${limit != null && limit > 0 ? limit : 40}';
      if (offset != null && offset > 0) query['offset'] = '$offset';

      final cacheKey = query.entries.map((e) => '${e.key}=${e.value}').join('&');
      final cacheFresh = _cachedItems != null &&
          _cachedItemsKey == cacheKey &&
          _cachedItemsAt != null &&
          DateTime.now().difference(_cachedItemsAt!) < const Duration(seconds: 45);
      if (cacheFresh) {
        return (
          items: _cachedItems!,
          total: _cachedItemsTotal > 0 ? _cachedItemsTotal : _cachedItems!.length,
        );
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
          _cachedItemsTotal = total;
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
    _cachedItemsTotal = 0;
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

  Future<bool> isOnline({Duration timeout = const Duration(seconds: 4)}) async {
    try {
      final response = await _get(
        _uri('/health'),
        timeout: timeout,
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<Order>> fetchOrders({DateTime? from}) async {
    try {
      final query = <String, String>{};
      final scoped = SuperAdminScopeService.instance.effectiveRestaurantId;
      final restaurantId = AdminAuthService.instance.restaurantId ??
          (scoped.isNotEmpty ? scoped : null);
      if (restaurantId != null && restaurantId.isNotEmpty) {
        query['restaurant_id'] = restaurantId;
      }
      if (from != null) {
        query['from'] = from.toUtc().toIso8601String();
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
            headers: _jsonHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 22));

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw _exceptionFromResponse(
          response,
          'فشل في حفظ الطلب (${response.statusCode})',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw Exception('استجابة غير متوقعة من السيرفر');
      }

      final map = Map<String, dynamic>.from(decoded);
      return Order.fromMap(map['id']?.toString() ?? '', map);
    } on ApiRequestException {
      rethrow;
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

  Future<Order?> updateOrderStatus(
    String orderId,
    OrderStatus status, {
    String? shiftId,
    String? cashierId,
    String? cashierName,
    bool autoAccepted = false,
    String? acceptedBy,
    String? acceptedByName,
  }) async {
    try {
      final response = await http
          .patch(
            _uri('/orders/$orderId/status'),
            headers: _jsonHeaders,
            body: jsonEncode({
              'status': autoAccepted ? 'auto_accepted' : status.name,
              if (autoAccepted) 'autoAccepted': true,
              if (acceptedBy != null && acceptedBy.isNotEmpty)
                'accepted_by': acceptedBy,
              if (acceptedByName != null && acceptedByName.isNotEmpty)
                'acceptedByName': acceptedByName,
              if (shiftId != null && shiftId.isNotEmpty) 'shiftId': shiftId,
              if (cashierId != null && cashierId.isNotEmpty) 'cashierId': cashierId,
              if (cashierName != null && cashierName.isNotEmpty)
                'cashierName': cashierName,
            }),
          )
          .timeout(_statusTimeout);

      if (response.statusCode != 200) {
        throw _exceptionFromResponse(response, 'فشل في تحديث الطلب');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        final id = map['id']?.toString().trim();
        return Order.fromMap(
          (id != null && id.isNotEmpty) ? id : orderId,
          map,
        );
      }
      return null;
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
    final payload = <String, dynamic>{
      'name': data['name'],
      'nameAr': data['nameAr'] ?? data['name_ar'],
      'nameEn': data['nameEn'] ?? data['name_en'],
      'name_ar': data['nameAr'] ?? data['name_ar'] ?? data['name'],
      'name_en': data['nameEn'] ?? data['name_en'] ?? '',
      'description': data['description'] ?? '',
      'descriptionAr': data['descriptionAr'] ?? data['description_ar'],
      'descriptionEn': data['descriptionEn'] ?? data['description_en'],
      'description_ar':
          data['descriptionAr'] ?? data['description_ar'] ?? data['description'] ?? '',
      'description_en': data['descriptionEn'] ?? data['description_en'] ?? '',
      'price': data['price'] ?? 0,
      'categoryName': data['categoryName'] ?? data['category_name'] ?? 'عام',
      'category_name': data['categoryName'] ?? data['category_name'] ?? 'عام',
      'imageUrl': data['imageUrl'] ?? data['image_url'] ?? '',
      'isAvailable': data['isAvailable'] ?? data['is_available'] ?? true,
      'showOnWebsite': data['showOnWebsite'] ?? data['show_on_website'] ?? true,
      'show_on_website': data['showOnWebsite'] ?? data['show_on_website'] ?? true,
      'source': data['source'] ?? 'Manual',
    };

    final costRaw = data['costPrice'] ?? data['cost_price'];
    final costPrice = costRaw is num
        ? costRaw.toDouble()
        : double.tryParse(costRaw?.toString() ?? '');
    if (costPrice != null && costPrice >= 0) {
      payload['costPrice'] = costPrice;
      payload['cost_price'] = costPrice;
    }

    final originalRaw = data['originalPrice'] ?? data['original_price'];
    final originalPrice = originalRaw is num
        ? originalRaw.toDouble()
        : double.tryParse(originalRaw?.toString() ?? '');
    if (originalPrice != null && originalPrice >= 0) {
      payload['originalPrice'] = originalPrice;
      payload['original_price'] = originalPrice;
    }

    if (data['options'] != null) {
      payload['options'] = data['options'];
    }
    final linked = data['linkedItemIds'] ?? data['linked_item_ids'];
    if (linked != null) {
      payload['linkedItemIds'] = linked;
      payload['linked_item_ids'] = linked;
    }
    final displayOrder = data['displayOrder'] ?? data['display_order'];
    if (displayOrder != null) {
      payload['displayOrder'] = displayOrder;
      payload['display_order'] = displayOrder;
    }

    return payload;
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
    bool? tableManagementEnabled,
    bool? kitchenManagementEnabled,
    bool? deliveryManagementEnabled,
    GeoPointLite? location,
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
            if (tableManagementEnabled != null)
              'tableManagement': tableManagementEnabled,
            if (kitchenManagementEnabled != null)
              'kitchenManagement': kitchenManagementEnabled,
            if (deliveryManagementEnabled != null)
              'deliveryManagement': deliveryManagementEnabled,
            if (location != null) 'location': location.toMap(),
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

  Map<String, dynamic> _decodeObject(http.Response response, String fallback) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _exceptionFromResponse(response, fallback);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<Map<String, dynamic>> getPublicJson(String path) async {
    final response = await _get(_uri(path), headers: _publicHeaders);
    return _decodeObject(response, 'فشل في تحميل البيانات');
  }

  Future<Map<String, dynamic>> postPublicJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http
        .post(_uri(path), headers: _publicHeaders, body: jsonEncode(body))
        .timeout(_writeTimeout);
    return _decodeObject(response, 'فشل في حفظ البيانات');
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    final response = await _get(_uri(path), headers: _jsonHeaders);
    return _decodeObject(response, 'فشل في تحميل البيانات');
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http
        .post(_uri(path), headers: _jsonHeaders, body: jsonEncode(body))
        .timeout(_writeTimeout);
    return _decodeObject(response, 'فشل في حفظ البيانات');
  }

  Future<String> uploadStoreAsset({
    required String restaurantId,
    required String kind,
    required String contentType,
    required String base64,
  }) async {
    final decoded = await postJson('/store-assets', {
      'restaurantId': restaurantId,
      'kind': kind,
      'contentType': contentType,
      'data': base64,
    });
    final url = decoded['url']?.toString().trim() ?? '';
    if (url.isEmpty) {
      throw Exception('تعذر رفع الصورة');
    }
    return url;
  }

  Future<String> uploadDriverDocument({
    required String driverId,
    required String kind,
    required String contentType,
    required String base64,
  }) async {
    final decoded = await postJson('/store-assets', {
      'driverId': driverId,
      'kind': kind,
      'contentType': contentType,
      'data': base64,
    });
    final url = decoded['url']?.toString().trim() ?? '';
    if (url.isEmpty) {
      throw Exception('تعذر رفع الصورة');
    }
    return url;
  }

  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http
        .put(_uri(path), headers: _jsonHeaders, body: jsonEncode(body))
        .timeout(_writeTimeout);
    return _decodeObject(response, 'فشل في حفظ البيانات');
  }

  Future<Map<String, dynamic>> patchJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http
        .patch(_uri(path), headers: _jsonHeaders, body: jsonEncode(body))
        .timeout(_writeTimeout);
    return _decodeObject(response, 'فشل في حفظ البيانات');
  }

  Future<Map<String, dynamic>> deleteJson(String path) async {
    final response = await http
        .delete(_uri(path), headers: _jsonHeaders)
        .timeout(_writeTimeout);
    return _decodeObject(response, 'فشل في الحذف');
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

  Future<List<MenuCategory>> fetchMenuCategories({
    String? restaurantId,
    bool syncFromItems = true,
  }) async {
    final scoped = _scopedRestaurantId(restaurantId: restaurantId);
    final query = <String, String>{
      'restaurant_id': scoped,
      if (syncFromItems) 'sync': '1' else 'sync': '0',
    };
    final response = await http
        .get(_uri('/menu-categories', query), headers: _jsonHeaders)
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر تحميل الأقسام');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((row) => MenuCategory.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<MenuCategory> createMenuCategory({
    required String restaurantId,
    required String name,
    String nameEn = '',
    int? sortOrder,
  }) async {
    final response = await http
        .post(
          _uri('/menu-categories'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'restaurantId': restaurantId,
            'name': name,
            'name_ar': name,
            'name_en': nameEn,
            if (sortOrder != null) 'sort_order': sortOrder,
          }),
        )
        .timeout(_writeTimeout);
    final decoded = jsonDecode(response.body);
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw _exceptionFromResponse(
        response,
        decoded is Map
            ? decoded['error']?.toString() ?? 'فشل إنشاء القسم'
            : 'فشل إنشاء القسم',
      );
    }
    if (decoded is! Map) throw Exception('استجابة غير متوقعة من السيرفر');
    return MenuCategory.fromMap(Map<String, dynamic>.from(decoded));
  }

  Future<MenuCategory> updateMenuCategory(
    String categoryId, {
    required String restaurantId,
    String? name,
    String? nameEn,
    int? sortOrder,
    bool? isActive,
  }) async {
    final response = await http
        .patch(
          _uri('/menu-categories/$categoryId'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'restaurantId': restaurantId,
            if (name != null) 'name': name,
            if (name != null) 'name_ar': name,
            if (nameEn != null) 'name_en': nameEn,
            if (sortOrder != null) 'sort_order': sortOrder,
            if (isActive != null) 'is_active': isActive,
          }),
        )
        .timeout(_writeTimeout);
    final decoded = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(
        response,
        decoded is Map
            ? decoded['error']?.toString() ?? 'فشل تحديث القسم'
            : 'فشل تحديث القسم',
      );
    }
    if (decoded is! Map) throw Exception('استجابة غير متوقعة من السيرفر');
    return MenuCategory.fromMap(Map<String, dynamic>.from(decoded));
  }

  Future<void> deleteMenuCategory(String categoryId) async {
    final response = await http
        .delete(_uri('/menu-categories/$categoryId'), headers: _jsonHeaders)
        .timeout(_writeTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'فشل حذف القسم');
    }
  }

  Future<void> reorderMenuCategories({
    required String restaurantId,
    required List<String> orderedIds,
  }) async {
    final response = await http
        .put(
          _uri('/menu-categories/reorder'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'restaurantId': restaurantId,
            'orderedIds': orderedIds,
          }),
        )
        .timeout(_writeTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'فشل حفظ ترتيب الأقسام');
    }
    invalidateItemsCache();
  }

  Future<void> reorderMenuItems({
    required String restaurantId,
    required List<String> orderedIds,
  }) async {
    final response = await http
        .put(
          _uri('/items/reorder'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'restaurantId': restaurantId,
            'orderedIds': orderedIds,
          }),
        )
        .timeout(_writeTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'فشل حفظ ترتيب الأصناف');
    }
    invalidateItemsCache();
  }

  Future<List<DeliveryZone>> fetchDeliveryZones({
    String? restaurantId,
    String? slug,
    bool activeOnly = true,
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

    final zones = decoded
        .whereType<Map>()
        .map((raw) => DeliveryZone.fromMap(Map<String, dynamic>.from(raw)))
        .toList();
    if (!activeOnly) return zones;
    return zones.where((zone) => zone.isActive).toList();
  }

  Future<DeliveryZone> createDeliveryZone(DeliveryZone zone) async {
    final scoped = _scopedRestaurantId(restaurantId: zone.restaurantId);
    final payload = zone.toMap()
      ..['restaurantId'] = scoped
      ..['restaurant_id'] = scoped
      ..['area_name'] = zone.areaName
      ..['delivery_fee'] = zone.deliveryFee
      ..['min_order'] = zone.minOrder
      ..['minOrder'] = zone.minOrder;
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
      ..['delivery_fee'] = zone.deliveryFee
      ..['min_order'] = zone.minOrder
      ..['minOrder'] = zone.minOrder;
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

  Future<List<Kitchen>> fetchKitchens({
    String? restaurantId,
    bool includeInactive = false,
  }) async {
    try {
      final query = {
        ..._restaurantQuery(restaurantId: restaurantId),
        if (includeInactive) 'include_inactive': '1',
      };
      final response = await http
          .get(_uri('/kitchens', query), headers: _jsonHeaders)
          .timeout(_fetchTimeout);
      if (response.statusCode != 200) {
        throw _exceptionFromResponse(
          response,
          'فشل في تحميل المطابخ (${response.statusCode})',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((raw) => Kitchen.fromMap(Map<String, dynamic>.from(raw)))
          .toList();
    } on TimeoutException {
      throw Exception('انتهت مهلة تحميل المطابخ');
    }
  }

  Future<Kitchen> saveKitchen({
    required Kitchen kitchen,
    String? restaurantId,
    String? pin,
  }) async {
    final scoped = _scopedRestaurantId(restaurantId: restaurantId);
    final payload = kitchen.toMap()
      ..['restaurant_id'] = scoped
      ..['restaurantId'] = scoped;
    if (pin != null && pin.trim().isNotEmpty) {
      payload['pin'] = pin.trim();
      payload['password'] = pin.trim();
    }
    final isUpdate = kitchen.id.isNotEmpty;
    final response = isUpdate
        ? await http
            .put(
              _uri('/kitchens/${kitchen.id}'),
              headers: _jsonHeaders,
              body: jsonEncode(payload),
            )
            .timeout(_writeTimeout)
        : await http
            .post(
              _uri('/kitchens'),
              headers: _jsonHeaders,
              body: jsonEncode(payload),
            )
            .timeout(_writeTimeout);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _exceptionFromResponse(
        response,
        isUpdate
            ? 'فشل في تحديث المطبخ (${response.statusCode})'
            : 'فشل في إضافة المطبخ (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw Exception('استجابة غير متوقعة من السيرفر');
    return Kitchen.fromMap(Map<String, dynamic>.from(decoded));
  }

  Future<void> deleteKitchen(String kitchenId) async {
    final response = await http
        .delete(_uri('/kitchens/$kitchenId'), headers: _jsonHeaders)
        .timeout(_writeTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(
        response,
        'فشل في حذف المطبخ (${response.statusCode})',
      );
    }
  }

  Future<void> deleteDeliveryZone(String zoneId) async {
    final response = await http
        .delete(_uri('/delivery-zones/$zoneId'), headers: _jsonHeaders)
        .timeout(_writeTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في حذف منطقة التوصيل (${response.statusCode})');
    }
  }

  Future<List<DeliveryDriver>> fetchDrivers({String? restaurantId}) async {
    final response = await http
        .get(_uri('/drivers'), headers: _jsonHeaders)
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر تحميل السائقين');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((row) => DeliveryDriver.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<MasterDeliveryRegion>> fetchMasterRegions() async {
    final response = await http
        .get(_uri('/master-regions'), headers: _jsonHeaders)
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر تحميل مناطق التوصيل');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((row) => MasterDeliveryRegion.fromJson(Map<String, dynamic>.from(row)))
        .where((row) => row.id.isNotEmpty)
        .toList();
  }

  Future<DeliveryDriver> createDriver({
    required String name,
    String phone = '',
    String civilId = '',
    String civilIdPhotoUrl = '',
    String licensePhotoUrl = '',
    String? restaurantId,
    String? pin,
    List<String> allowedDeliveryRegions = const [],
    Map<String, bool>? assignedRegions,
  }) async {
    final response = await http
        .post(
          _uri('/drivers'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'name': name,
            'phone': phone,
            'civil_id': civilId,
            'civil_id_photo_url': civilIdPhotoUrl,
            'license_photo_url': licensePhotoUrl,
            if (pin != null && pin.trim().isNotEmpty) 'pin': pin.trim(),
            if (assignedRegions != null) 'assigned_regions': assignedRegions,
            'allowed_delivery_regions': allowedDeliveryRegions,
          }),
        )
        .timeout(_writeTimeout);
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر إضافة السائق');
    }
    return DeliveryDriver.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<void> deleteDriver(String id) async {
    final response = await http
        .delete(_uri('/drivers/$id'), headers: _jsonHeaders)
        .timeout(_writeTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر حذف السائق');
    }
  }

  Future<DeliveryDriver> patchDriver(
    String id, {
    bool? isOnline,
    bool? isBusy,
    GeoPointLite? location,
    String? fcmToken,
    String? name,
    String? phone,
    String? civilId,
    String? civilIdPhotoUrl,
    String? licensePhotoUrl,
    List<String>? allowedDeliveryRegions,
    Map<String, bool>? assignedRegions,
  }) async {
    final body = <String, dynamic>{
      if (isOnline != null) 'is_online': isOnline,
      if (isBusy != null) 'is_busy': isBusy,
      if (location != null) 'current_location': location.toMap(),
      if (fcmToken != null && fcmToken.isNotEmpty) 'fcm_token': fcmToken,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (civilId != null) 'civil_id': civilId,
      if (civilIdPhotoUrl != null) 'civil_id_photo_url': civilIdPhotoUrl,
      if (licensePhotoUrl != null) 'license_photo_url': licensePhotoUrl,
      if (assignedRegions != null) 'assigned_regions': assignedRegions,
      if (allowedDeliveryRegions != null && assignedRegions == null)
        'allowed_delivery_regions': allowedDeliveryRegions,
    };
    final response = await http
        .patch(_uri('/drivers/$id'), headers: _jsonHeaders, body: jsonEncode(body))
        .timeout(_writeTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر تحديث السائق');
    }
    return DeliveryDriver.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<List<DeliveryDispatchRequest>> fetchDeliveryRequests({String? restaurantId}) async {
    final response = await http
        .get(
          _uri('/delivery-requests', _restaurantQuery(restaurantId: restaurantId)),
          headers: _jsonHeaders,
        )
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر تحميل طلبات التوصيل');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((row) => DeliveryDispatchRequest.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<DeliveryDispatchRequest> createDeliveryRequest({
    required String customerPhone,
    String? regionId,
    String? regionName,
    String? orderId,
    bool isExpress = false,
    double cashToCollect = 0,
    String? customerAddress,
    String? restaurantId,
  }) async {
    final response = await http
        .post(
          _uri('/delivery-requests'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'customer_phone': customerPhone,
            'region_id': regionId,
            'region_name': regionName,
            'order_id': orderId,
            'is_express': isExpress,
            'cash_to_collect': cashToCollect,
            'customer_address': customerAddress,
            'restaurantId': _scopedRestaurantId(restaurantId: restaurantId),
          }),
        )
        .timeout(_writeTimeout);
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر إنشاء طلب التوصيل');
    }
    return DeliveryDispatchRequest.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  Future<DeliveryDispatchRequest> assignDeliveryDriver({
    required String requestId,
    required String driverId,
  }) async {
    final response = await http
        .post(
          _uri('/delivery-requests/$requestId/assign'),
          headers: _jsonHeaders,
          body: jsonEncode({'driver_id': driverId}),
        )
        .timeout(_writeTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر تعيين السائق');
    }
    return DeliveryDispatchRequest.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  Future<Map<String, dynamic>> fetchDriverInbox() async {
    final response = await http
        .get(_uri('/me/driver'), headers: _jsonHeaders)
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر تحميل شاشة السائق');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<FleetOpsSnapshot> fetchFleetOps() async {
    final response = await http
        .get(_uri('/fleet/ops'), headers: _jsonHeaders)
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر تحميل مركز الأسطول');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return const FleetOpsSnapshot();
    return FleetOpsSnapshot.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<DeliveryDriver> controlDriver(
    String driverId, {
    required String action,
    int? minutes,
    String? status,
  }) async {
    final response = await http
        .post(
          _uri('/drivers/$driverId/control'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'action': action,
            if (minutes != null) 'minutes': minutes,
            if (status != null) 'status': status,
          }),
        )
        .timeout(_writeTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر تنفيذ إجراء التحكم');
    }
    return DeliveryDriver.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<DeliveryDispatchRequest> postDeliveryAction(String requestId, String action) async {
    final response = await http
        .post(
          _uri('/delivery-requests/$requestId/$action'),
          headers: _jsonHeaders,
          body: jsonEncode({}),
        )
        .timeout(_writeTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر تحديث طلب التوصيل');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['ok'] == true) {
      return DeliveryDispatchRequest(id: requestId, status: 'pending');
    }
    return DeliveryDispatchRequest.fromJson(Map<String, dynamic>.from(decoded as Map));
  }

  Future<List<DriverLedgerEntry>> fetchDriverLedger(
    String driverId, {
    String? from,
    String? to,
    String? restaurant,
    String? orderId,
  }) async {
    final query = <String, String>{
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (restaurant != null && restaurant.isNotEmpty) 'restaurant': restaurant,
      if (orderId != null && orderId.isNotEmpty) 'order_id': orderId,
    };
    final response = await http
        .get(_uri('/drivers/$driverId/ledger', query), headers: _jsonHeaders)
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر تحميل السجل المالي');
    }
    final decoded = jsonDecode(response.body);
    final entries = decoded is Map ? decoded['entries'] : decoded;
    if (entries is! List) return const [];
    return entries
        .whereType<Map>()
        .map((row) => DriverLedgerEntry.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<Offer>> fetchOffers({
    String? restaurantId,
    bool activeOnly = true,
  }) async {
    final query = {
      ..._restaurantQuery(restaurantId: restaurantId),
      if (!activeOnly) 'includeInactive': '1',
    };
    final response = await http
        .get(_uri('/offers', query), headers: _publicHeaders)
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) {
      throw Exception('فشل في تحميل العروض (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    final offers = decoded
        .whereType<Map>()
        .map((raw) => Offer.fromMap(Map<String, dynamic>.from(raw)))
        .toList();
    if (!activeOnly) return offers;
    return offers.where((offer) => offer.isLive).toList();
  }

  Future<List<Offer>> fetchAdminOffers({String? restaurantId}) async {
    final query = _restaurantQuery(restaurantId: restaurantId);
    final response = await http
        .get(_uri('/admin/offers', query), headers: _jsonHeaders)
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) {
      return fetchOffers(restaurantId: restaurantId, activeOnly: false);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((raw) => Offer.fromMap(Map<String, dynamic>.from(raw)))
        .toList();
  }

  Future<Offer> saveOffer(Offer offer, {required bool isUpdate}) async {
    final scoped = _scopedRestaurantId(restaurantId: offer.restaurantId);
    final payload = offer.toMap()
      ..['action'] = isUpdate ? 'update' : 'create'
      ..['restaurantId'] = scoped
      ..['restaurant_id'] = scoped;

    final response = await http
        .post(
          _uri('/admin/offers'),
          headers: _jsonHeaders,
          body: jsonEncode(payload),
        )
        .timeout(_writeTimeout);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('فشل في حفظ العرض (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    return Offer.fromMap(Map<String, dynamic>.from(decoded));
  }

  Future<void> deleteOffer(String offerId) async {
    final response = await http
        .post(
          _uri('/admin/offers'),
          headers: _jsonHeaders,
          body: jsonEncode({'action': 'delete', 'id': offerId}),
        )
        .timeout(_writeTimeout);
    if (response.statusCode != 200) {
      throw Exception('فشل في حذف العرض (${response.statusCode})');
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

  Future<PnlReport> fetchPnlReport({
    String? restaurantId,
    int days = 30,
  }) async {
    final map = await _getJsonMap(
      '/analytics/pnl',
      query: {
        ..._restaurantQuery(restaurantId: restaurantId),
        'days': '$days',
      },
    );
    return PnlReport.fromJson(map);
  }

  Future<List<ExpenseRecord>> fetchExpenses({
    String? restaurantId,
    String? category,
    String? from,
    String? to,
  }) async {
    final query = {
      ..._restaurantQuery(restaurantId: restaurantId),
      if (category != null && category.isNotEmpty) 'category': category,
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
    };
    final response = await http
        .get(_uri('/expenses', query), headers: _jsonHeaders)
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) {
      throw Exception('فشل تحميل المصاريف (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body);
    final raw = decoded is Map ? decoded['expenses'] : decoded;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => ExpenseRecord.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<ExpenseRecord> createExpense(
    ExpenseRecord expense, {
    String? restaurantId,
  }) async {
    final scoped = _scopedRestaurantId(restaurantId: restaurantId);
    final response = await http
        .post(
          _uri('/expenses', {'restaurant_id': scoped}),
          headers: _jsonHeaders,
          body: jsonEncode({
            ...expense.toJson(),
            'restaurantId': scoped,
            'restaurant_id': scoped,
          }),
        )
        .timeout(_fetchTimeout);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('فشل إضافة المصروف (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw Exception('استجابة غير متوقعة من السيرفر');
    return ExpenseRecord.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<void> deleteExpense(String expenseId, {String? restaurantId}) async {
    final scoped = _scopedRestaurantId(restaurantId: restaurantId);
    final response = await http
        .delete(
          _uri('/expenses/$expenseId', {'restaurant_id': scoped}),
          headers: _jsonHeaders,
        )
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) {
      throw Exception('فشل حذف المصروف (${response.statusCode})');
    }
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

  Future<ReviewSummary> fetchReviewSummary({
    String? restaurantId,
    String? slug,
  }) async {
    final query = _publicRestaurantQuery(slug: slug, restaurantId: restaurantId);
    final response = await http
        .get(
          _uri('/reviews/summary', query.isEmpty ? null : query),
          headers: _publicHeaders,
        )
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) {
      return const ReviewSummary();
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return const ReviewSummary();
    return ReviewSummary.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<ReviewEligibility> fetchReviewEligibility({
    required String orderId,
    String? restaurantId,
    String? slug,
  }) async {
    final query = {
      ..._publicRestaurantQuery(slug: slug, restaurantId: restaurantId),
      'orderId': orderId,
    };
    final response = await http
        .get(
          _uri('/reviews/eligibility', query),
          headers: _publicHeaders,
        )
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) {
      return const ReviewEligibility(eligible: false, reason: 'request_failed');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      return const ReviewEligibility(eligible: false, reason: 'invalid_response');
    }
    return ReviewEligibility.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<ReviewSummary> submitRestaurantReview({
    required String orderId,
    required int rating,
    required String restaurantId,
    String? slug,
    String comment = '',
    String customerName = '',
    String phone = '',
  }) async {
    final payload = <String, dynamic>{
      'orderId': orderId,
      'rating': rating,
      'comment': comment,
      'restaurantId': restaurantId,
      'restaurant_id': restaurantId,
      if (slug != null && slug.trim().isNotEmpty) 'restaurantSlug': slug.trim(),
      if (customerName.trim().isNotEmpty) 'customerName': customerName.trim(),
      if (phone.trim().isNotEmpty) 'phone': phone.trim(),
    };
    final response = await http
        .post(
          _uri('/reviews'),
          headers: _publicHeaders,
          body: jsonEncode(payload),
        )
        .timeout(_fetchTimeout);
    if (response.statusCode != 200 && response.statusCode != 201) {
      final decoded = jsonDecode(response.body);
      final message = decoded is Map
          ? (decoded['error']?.toString() ?? 'فشل إرسال التقييم')
          : 'فشل إرسال التقييم (${response.statusCode})';
      throw Exception(message);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['summary'] is Map) {
      return ReviewSummary.fromJson(
        Map<String, dynamic>.from(decoded['summary'] as Map),
      );
    }
    return const ReviewSummary();
  }

  Future<Map<String, dynamic>> createOrderRatingLink(String orderId) async {
    final response = await http
        .post(
          _uri('/orders/${Uri.encodeComponent(orderId)}/rating-link'),
          headers: _jsonHeaders,
          body: jsonEncode({}),
        )
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'تعذر إنشاء رابط التقييم');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const ApiRequestException('رد غير صالح');
    return Map<String, dynamic>.from(decoded);
  }

  Future<OrderRatingPageData> fetchOrderRatingPage({
    required String orderId,
    required String token,
  }) async {
    final response = await http
        .get(
          _uri(
            '/orders/${Uri.encodeComponent(orderId)}/rating',
            {'token': token},
          ),
          headers: _publicHeaders,
        )
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response, 'رابط التقييم غير صالح');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const ApiRequestException('رد غير صالح');
    return OrderRatingPageData.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<OrderRatingPageData> submitOrderRating({
    required String orderId,
    required String token,
    required int rating,
    String reviewNote = '',
  }) async {
    final response = await http
        .post(
          _uri('/orders/${Uri.encodeComponent(orderId)}/rating'),
          headers: _publicHeaders,
          body: jsonEncode({
            'token': token,
            'rating': rating,
            'review_note': reviewNote,
          }),
        )
        .timeout(_fetchTimeout);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _exceptionFromResponse(response, 'تعذر حفظ التقييم');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const ApiRequestException('رد غير صالح');
    return OrderRatingPageData.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<AdminReviewsPayload> fetchAdminReviews({
    String? restaurantId,
    int days = 30,
    bool includeHidden = true,
  }) async {
    final scoped = _scopedRestaurantId(restaurantId: restaurantId);
    final query = <String, String>{
      if (scoped.isNotEmpty) 'restaurant_id': scoped,
      'days': '$days',
      'includeHidden': includeHidden ? 'true' : 'false',
    };
    final response = await http
        .get(_uri('/reviews', query), headers: _jsonHeaders)
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) {
      throw Exception('فشل تحميل التقييمات (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    return AdminReviewsPayload.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<void> updateReviewStatus({
    required String reviewId,
    required String status,
    String? restaurantId,
  }) async {
    final scoped = _scopedRestaurantId(restaurantId: restaurantId);
    final query = scoped.isEmpty ? null : {'restaurant_id': scoped};
    final response = await http
        .patch(
          _uri('/reviews/$reviewId', query),
          headers: _jsonHeaders,
          body: jsonEncode({'status': status}),
        )
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) {
      throw Exception('فشل تحديث التقييم (${response.statusCode})');
    }
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

