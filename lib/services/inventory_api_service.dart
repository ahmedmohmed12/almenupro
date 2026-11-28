import 'dart:convert';

import 'package:http/http.dart' as http;

import 'admin_auth_service.dart';
import 'api_service.dart';
import 'super_admin_scope_service.dart';

/// REST client for `/api/inventory/*` (Foodics-style AVCO module).
class InventoryApiService {
  InventoryApiService._();

  static final InventoryApiService instance = InventoryApiService._();

  static const inventoryChannels = [
    'ALL',
    'DINE_IN',
    'TAKEAWAY',
    'DELIVERY',
    'AGGREGATOR',
  ];

  static const wasteReasons = [
    'SPOILAGE',
    'EXPIRED',
    'PREPARATION_ERROR',
    'CUSTOMER_RETURN',
    'OVERPRODUCTION',
    'OTHER',
  ];

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        ...AdminAuthService.instance.authHeaders,
        ...SuperAdminScopeService.instance.scopeHeaders,
      };

  Uri _uri(String path, {String? restaurantId, Map<String, String>? query}) {
    final scoped =
        restaurantId ?? SuperAdminScopeService.instance.effectiveRestaurantId;
    return Uri.parse('${ApiService.baseUrl}$path').replace(
      queryParameters: {
        'restaurant_id': scoped,
        if (query != null) ...query,
      },
    );
  }

  Exception _fail(http.Response response, String fallback) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] != null) {
        return Exception(decoded['error'].toString());
      }
    } catch (_) {}
    return Exception('$fallback (${response.statusCode})');
  }

  Future<bool> fetchEnabled({String? restaurantId}) async {
    final response = await http
        .get(_uri('/inventory/status', restaurantId: restaurantId), headers: _headers)
        .timeout(const Duration(seconds: 18));
    if (response.statusCode != 200) return false;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return false;
    return decoded['inventoryEnabled'] == true;
  }

  Future<List<Map<String, dynamic>>> fetchItems({String? restaurantId}) async {
    final response = await http
        .get(_uri('/inventory/items', restaurantId: restaurantId), headers: _headers)
        .timeout(const Duration(seconds: 45));
    if (response.statusCode == 403) {
      throw _fail(response, 'المخزون غير مفعّل');
    }
    if (response.statusCode != 200) throw _fail(response, 'فشل تحميل الأصناف');
    final decoded = jsonDecode(response.body);
    final raw = decoded is Map ? decoded['items'] : decoded;
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> createItem(
    Map<String, dynamic> body, {
    String? restaurantId,
  }) async {
    final response = await http
        .post(
          _uri('/inventory/items', restaurantId: restaurantId),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw _fail(response, 'فشل إضافة الصنف');
    }
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<Map<String, dynamic>?> fetchMenuRecipe(
    String menuItemId, {
    String? restaurantId,
  }) async {
    final response = await http
        .get(
          _uri('/inventory/recipes/menu/$menuItemId', restaurantId: restaurantId),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw _fail(response, 'فشل تحميل الوصفة');
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return null;
    return Map<String, dynamic>.from(decoded);
  }

  Future<List<Map<String, dynamic>>> fetchRecipes({String? restaurantId}) async {
    final response = await http
        .get(_uri('/inventory/recipes', restaurantId: restaurantId), headers: _headers)
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) throw _fail(response, 'فشل تحميل الوصفات');
    final decoded = jsonDecode(response.body);
    final raw = decoded is Map ? decoded['recipes'] : decoded;
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> saveRecipe(
    Map<String, dynamic> body, {
    String? restaurantId,
  }) async {
    final response = await http
        .post(
          _uri('/inventory/recipes', restaurantId: restaurantId),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) throw _fail(response, 'فشل حفظ الوصفة');
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<Map<String, dynamic>> estimateMenuCost({
    required String menuItemId,
    String channel = 'TAKEAWAY',
    String? restaurantId,
  }) async {
    final response = await http
        .post(
          _uri('/inventory/recipes/estimate-cost', restaurantId: restaurantId),
          headers: _headers,
          body: jsonEncode({'menuItemId': menuItemId, 'channel': channel}),
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) throw _fail(response, 'فشل تقدير التكلفة');
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<List<Map<String, dynamic>>> fetchPurchases({String? restaurantId}) async {
    final response = await http
        .get(_uri('/inventory/purchases', restaurantId: restaurantId), headers: _headers)
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) throw _fail(response, 'فشل تحميل المشتريات');
    final decoded = jsonDecode(response.body);
    final raw = decoded is Map ? decoded['purchases'] : decoded;
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> createPurchase(
    Map<String, dynamic> body, {
    String? restaurantId,
  }) async {
    final response = await http
        .post(
          _uri('/inventory/purchases', restaurantId: restaurantId),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw _fail(response, 'فشل إنشاء أمر الشراء');
    }
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<Map<String, dynamic>> patchPurchase(
    String purchaseId,
    Map<String, dynamic> body, {
    String? restaurantId,
  }) async {
    final response = await http
        .patch(
          _uri('/inventory/purchases/$purchaseId', restaurantId: restaurantId),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw _fail(response, 'فشل تعديل أمر الشراء');
    }
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<Map<String, dynamic>> closePurchase(
    String purchaseId, {
    String? restaurantId,
  }) async {
    final response = await http
        .post(
          _uri('/inventory/purchases/$purchaseId/close', restaurantId: restaurantId),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) throw _fail(response, 'فشل إغلاق الشراء');
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<List<Map<String, dynamic>>> fetchTransfers({String? restaurantId}) async {
    final response = await http
        .get(_uri('/inventory/transfers', restaurantId: restaurantId), headers: _headers)
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) throw _fail(response, 'فشل تحميل التحويلات');
    final decoded = jsonDecode(response.body);
    final raw = decoded is Map ? decoded['transfers'] : decoded;
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> createTransfer(
    Map<String, dynamic> body, {
    String? restaurantId,
  }) async {
    final response = await http
        .post(
          _uri('/inventory/transfers', restaurantId: restaurantId),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw _fail(response, 'فشل إنشاء التحويل');
    }
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<Map<String, dynamic>> patchTransfer(
    String transferId,
    Map<String, dynamic> body, {
    String? restaurantId,
  }) async {
    final response = await http
        .patch(
          _uri('/inventory/transfers/$transferId', restaurantId: restaurantId),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw _fail(response, 'فشل تعديل التحويل');
    }
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<Map<String, dynamic>> sendTransfer(
    String transferId, {
    String? restaurantId,
  }) async {
    final response = await http
        .post(
          _uri('/inventory/transfers/$transferId/send', restaurantId: restaurantId),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) throw _fail(response, 'فشل إرسال التحويل');
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<Map<String, dynamic>> receiveTransfer(
    String transferId, {
    String? restaurantId,
  }) async {
    final response = await http
        .post(
          _uri('/inventory/transfers/$transferId/receive', restaurantId: restaurantId),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) throw _fail(response, 'فشل استلام التحويل');
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<List<Map<String, dynamic>>> fetchProductions({String? restaurantId}) async {
    final response = await http
        .get(_uri('/inventory/productions', restaurantId: restaurantId), headers: _headers)
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) throw _fail(response, 'فشل تحميل الإنتاج');
    final decoded = jsonDecode(response.body);
    final raw = decoded is Map ? decoded['productions'] : decoded;
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> createProduction(
    Map<String, dynamic> body, {
    String? restaurantId,
  }) async {
    final response = await http
        .post(
          _uri('/inventory/productions', restaurantId: restaurantId),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw _fail(response, 'فشل إنشاء الإنتاج');
    }
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<Map<String, dynamic>> patchProduction(
    String productionId,
    Map<String, dynamic> body, {
    String? restaurantId,
  }) async {
    final response = await http
        .patch(
          _uri('/inventory/productions/$productionId', restaurantId: restaurantId),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw _fail(response, 'فشل تعديل الإنتاج');
    }
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<Map<String, dynamic>> closeProduction(
    String productionId, {
    String? restaurantId,
  }) async {
    final response = await http
        .post(
          _uri('/inventory/productions/$productionId/close', restaurantId: restaurantId),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) throw _fail(response, 'فشل إغلاق الإنتاج');
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<List<Map<String, dynamic>>> fetchWasteDocuments({String? restaurantId}) async {
    final response = await http
        .get(_uri('/inventory/waste-documents', restaurantId: restaurantId), headers: _headers)
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) throw _fail(response, 'فشل تحميل الهالك');
    final decoded = jsonDecode(response.body);
    final raw = decoded is Map ? decoded['documents'] : decoded;
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> createWasteDocument(
    Map<String, dynamic> body, {
    String? restaurantId,
  }) async {
    final response = await http
        .post(
          _uri('/inventory/waste-documents', restaurantId: restaurantId),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw _fail(response, 'فشل إنشاء وثيقة الهالك');
    }
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<Map<String, dynamic>> patchWasteDocument(
    String wasteId,
    Map<String, dynamic> body, {
    String? restaurantId,
  }) async {
    final response = await http
        .patch(
          _uri('/inventory/waste-documents/$wasteId', restaurantId: restaurantId),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw _fail(response, 'فشل تعديل وثيقة الهالك');
    }
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<Map<String, dynamic>> closeWasteDocument(
    String wasteId, {
    String? restaurantId,
  }) async {
    final response = await http
        .post(
          _uri('/inventory/waste-documents/$wasteId/close', restaurantId: restaurantId),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) throw _fail(response, 'فشل إغلاق الهالك');
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<List<Map<String, dynamic>>> fetchCounts({String? restaurantId}) async {
    final response = await http
        .get(_uri('/inventory/counts', restaurantId: restaurantId), headers: _headers)
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) throw _fail(response, 'فشل تحميل الجرد');
    final decoded = jsonDecode(response.body);
    final raw = decoded is Map ? decoded['counts'] : decoded;
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> createCount(
    Map<String, dynamic> body, {
    String? restaurantId,
  }) async {
    final response = await http
        .post(
          _uri('/inventory/counts', restaurantId: restaurantId),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw _fail(response, 'فشل إنشاء الجرد');
    }
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<Map<String, dynamic>> patchCount(
    String countId,
    Map<String, dynamic> body, {
    String? restaurantId,
  }) async {
    final response = await http
        .patch(
          _uri('/inventory/counts/$countId', restaurantId: restaurantId),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw _fail(response, 'فشل تعديل الجرد');
    }
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<Map<String, dynamic>> closeCount(
    String countId, {
    String? restaurantId,
  }) async {
    final response = await http
        .post(
          _uri('/inventory/counts/$countId/close', restaurantId: restaurantId),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) throw _fail(response, 'فشل إغلاق الجرد');
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<List<Map<String, dynamic>>> reportLevels({
    String? restaurantId,
    String? category,
  }) async {
    final response = await http
        .get(
          _uri(
            '/inventory/reports/levels',
            restaurantId: restaurantId,
            query: {if (category != null && category.isNotEmpty) 'category': category},
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) throw _fail(response, 'فشل تقرير المستويات');
    final decoded = jsonDecode(response.body);
    final raw = decoded is Map ? decoded['rows'] : decoded;
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> reportCogs({
    String? restaurantId,
    String? from,
    String? to,
    String? category,
  }) async {
    final response = await http
        .get(
          _uri(
            '/inventory/reports/cogs',
            restaurantId: restaurantId,
            query: {
              if (from != null && from.isNotEmpty) 'from': from,
              if (to != null && to.isNotEmpty) 'to': to,
              if (category != null && category.isNotEmpty) 'category': category,
            },
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) throw _fail(response, 'فشل تقرير التكلفة');
    final decoded = jsonDecode(response.body);
    final raw = decoded is Map ? decoded['rows'] : decoded;
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> reportHistory({
    String? restaurantId,
    String? itemId,
    String? from,
    String? to,
  }) async {
    final response = await http
        .get(
          _uri(
            '/inventory/reports/history',
            restaurantId: restaurantId,
            query: {
              if (itemId != null && itemId.isNotEmpty) 'itemId': itemId,
              if (from != null && from.isNotEmpty) 'from': from,
              if (to != null && to.isNotEmpty) 'to': to,
            },
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) throw _fail(response, 'فشل سجل الحركات');
    final decoded = jsonDecode(response.body);
    final raw = decoded is Map ? decoded['rows'] : decoded;
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> reportPurchasingWaste({
    String? restaurantId,
    String? from,
    String? to,
    String? category,
  }) async {
    final response = await http
        .get(
          _uri(
            '/inventory/reports/purchasing-waste',
            restaurantId: restaurantId,
            query: {
              if (from != null && from.isNotEmpty) 'from': from,
              if (to != null && to.isNotEmpty) 'to': to,
              if (category != null && category.isNotEmpty) 'category': category,
            },
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) throw _fail(response, 'فشل تقرير المشتريات والهالك');
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return const {};
    return Map<String, dynamic>.from(decoded);
  }

  Future<List<Map<String, dynamic>>> reportVariance({
    String? restaurantId,
    String? from,
    String? to,
    String? category,
  }) async {
    final response = await http
        .get(
          _uri(
            '/inventory/reports/variance',
            restaurantId: restaurantId,
            query: {
              if (from != null && from.isNotEmpty) 'from': from,
              if (to != null && to.isNotEmpty) 'to': to,
              if (category != null && category.isNotEmpty) 'category': category,
            },
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) throw _fail(response, 'فشل تقرير الانحراف');
    final decoded = jsonDecode(response.body);
    final raw = decoded is Map ? decoded['rows'] : decoded;
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
}