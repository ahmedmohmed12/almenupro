import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/kitchen_void_liability.dart';
import '../models/pos_approval_request.dart';
import '../models/pos_permission_catalog.dart';
import '../models/pos_role.dart';
import '../models/shift_session.dart';
import '../models/staff_user.dart';
import 'admin_auth_service.dart';
import 'api_service.dart';
import 'hr_controller.dart';
import 'super_admin_scope_service.dart';

class PosOperationsService extends ChangeNotifier {
  PosOperationsService._();

  static final PosOperationsService instance = PosOperationsService._();

  PosCashierSession? _cashierSession;
  ShiftSession? _activeShift;

  PosCashierSession? get cashierSession => _cashierSession;
  ShiftSession? get activeShift => _activeShift;

  Map<String, bool> get effectivePermissions {
    final session = _cashierSession;
    if (session != null) {
      return PosPermissionCatalog.normalizePermissions(session.permissions);
    }
    if (AdminAuthService.instance.isRestaurantAdmin ||
        AdminAuthService.instance.isSuperAdmin) {
      return PosPermissionCatalog.fullAccessMap();
    }
    return const {};
  }

  bool allows(String permission) {
    return PosPermissionCatalog.roleAllows(effectivePermissions, permission);
  }

  void _notifySessionChanged() => notifyListeners();

  void setCashierSession(PosCashierSession? session) {
    _cashierSession = session;
    _notifySessionChanged();
  }

  Map<String, bool> _ensurePosAccess(Map<String, bool> permissions) {
    if (permissions[PosPermissionKeys.posAccess] == true ||
        permissions[PosPermissionKeys.processOrders] == true) {
      return PosPermissionCatalog.normalizePermissions(
        Map<String, dynamic>.from(permissions),
      );
    }
    return PosPermissionCatalog.normalizePermissions(
      Map<String, dynamic>.from(PosRole.defaults().first.permissions),
    );
  }

  void applyCashierSession(PosCashierSession session) {
    final permissions = _ensurePosAccess(session.permissions);
    _cashierSession = PosCashierSession(
      staff: session.staff,
      permissions: permissions,
      roleId: session.roleId.isNotEmpty ? session.roleId : 'cashier',
    );
    _notifySessionChanged();
    if (AdminAuthService.instance.isCashier) {
      AdminAuthService.instance.persistCashierPermissions(
        permissions,
        roleId: _cashierSession!.roleId,
      );
    }
  }

  Future<void> restoreCashierSessionIfNeeded() async {
    if (_cashierSession != null) return;
    final session = AdminAuthService.instance.session;
    if (session == null || !session.isCashier) return;
    final stored = await AdminAuthService.instance.loadCashierPermissions();
    applyCashierSession(
      PosCashierSession(
        staff: StaffUser(
          id: session.staffId ?? 'cashier',
          name: session.staffName ?? 'كاشير',
          roleId: stored?.roleId.isNotEmpty == true ? stored!.roleId : 'cashier',
        ),
        permissions: stored?.permissions ?? const {},
        roleId: stored?.roleId ?? 'cashier',
      ),
    );
  }

  void clearCashierSession() {
    final hadSession = _cashierSession != null;
    _cashierSession = null;
    _activeShift = null;
    _notifySessionChanged();
    if (hadSession) _noteHrPinCheckOut();
  }

  void setActiveShift(ShiftSession? shift) {
    _activeShift = shift;
    _notifySessionChanged();
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        ...AdminAuthService.instance.authHeaders,
        ...SuperAdminScopeService.instance.scopeHeaders,
      };

  Uri _posUri(
    String path, {
    Map<String, String>? query,
    bool scoped = true,
  }) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final params = {...?query};
    if (scoped) {
      final restaurantId = SuperAdminScopeService.instance.effectiveRestaurantId;
      if (restaurantId.isNotEmpty) {
        params['restaurant_id'] = restaurantId;
      }
    }
    return Uri.parse('${ApiService.baseUrl}$normalizedPath')
        .replace(queryParameters: params.isEmpty ? null : params);
  }

  Future<void> syncCashierPermissionsFromServer() async {
    if (!AdminAuthService.instance.isLoggedIn) return;

    try {
      final response = await http
          .get(_posUri('/pos/session/permissions'), headers: _headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return;

      final map = Map<String, dynamic>.from(decoded);
      final permissions = PosPermissionCatalog.normalizePermissions(
        map['permissions'] is Map
            ? Map<String, dynamic>.from(map['permissions'] as Map)
            : null,
      );

      final roleId = map['roleId']?.toString() ?? '';
      final existing = _cashierSession;

      if (existing != null) {
        applyCashierSession(
          PosCashierSession(
            staff: existing.staff,
            permissions: permissions,
            roleId: roleId.isNotEmpty ? roleId : existing.roleId,
          ),
        );
      } else if (AdminAuthService.instance.isRestaurantAdmin ||
          AdminAuthService.instance.isSuperAdmin) {
        await bootstrapAdminCashier(permissions: permissions);
      }

      await AdminAuthService.instance.persistCashierPermissions(permissions, roleId: roleId);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('POS permission sync failed: $error');
      }
    }
  }

  Future<PosCashierSession> loginWithPin(
    String pin, {
    String? cashierName,
    String? restaurantName,
  }) async {
    final password = pin.trim();
    final name = cashierName?.trim() ?? '';
    final restaurant = restaurantName?.trim() ?? '';
    final auth = AdminAuthService.instance;

    final useCashierJwtLogin = restaurant.isNotEmpty &&
        name.isNotEmpty &&
        (!auth.isLoggedIn || auth.isCashier);

    if (useCashierJwtLogin) {
      final result = await auth.loginCashier(
        restaurantName: restaurant,
        cashierName: name,
        password: password,
      );
      applyCashierSession(result.cashierSession);
      _noteHrPinCheckIn(password);
      return result.cashierSession;
    }

    if (!auth.isLoggedIn) {
      throw Exception('يرجى إدخال اسم المطعم واسم الكاشير وكلمة المرور');
    }

    final response = await http
        .post(
          _posUri('/pos/staff/login'),
          headers: _headers,
          body: jsonEncode({
            'pin': password,
            'password': password,
            if (name.isNotEmpty) 'cashierName': name,
            if (name.isNotEmpty) 'name': name,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل تسجيل دخول الكاشير'));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    final session = PosCashierSession.fromJson(Map<String, dynamic>.from(decoded));
    applyCashierSession(session);
    _noteHrPinCheckIn(password);
    return session;
  }

  void _noteHrPinCheckIn(String pin) {
    HrController.instance.recordPinCheckIn(pin, DateTime.now()).catchError((Object error) {
      if (kDebugMode) debugPrint('HR PIN check-in skipped: $error');
      return null;
    });
  }

  void _noteHrPinCheckOut() {
    HrController.instance.recordPinCheckOut(DateTime.now()).catchError((Object error) {
      if (kDebugMode) debugPrint('HR PIN check-out skipped: $error');
    });
  }

  Future<ManagerOverrideResult> requestManagerOverride({
    required String pin,
    required String action,
    String? entityId,
    String? performedById,
    String? performedByName,
  }) async {
    final response = await http
        .post(
          _posUri('/pos/override'),
          headers: _headers,
          body: jsonEncode({
            'pin': pin.trim(),
            'action': action,
            if (entityId != null) 'entityId': entityId,
            if (performedById != null) 'performedById': performedById,
            if (performedByName != null) 'performedByName': performedByName,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشلت موافقة المشرف'));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    return ManagerOverrideResult.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<ShiftSession?> fetchCurrentShift({String? cashierId}) async {
    final response = await http
        .get(
          _posUri(
            '/pos/shifts/current',
            query: {
              if (cashierId != null && cashierId.isNotEmpty) 'cashierId': cashierId,
            },
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل تحميل الوردية'));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return null;
    final rawShift = decoded['shift'];
    if (rawShift is! Map) {
      _activeShift = null;
      _notifySessionChanged();
      return null;
    }
    _activeShift = ShiftSession.fromJson(Map<String, dynamic>.from(rawShift));
    _notifySessionChanged();
    return _activeShift;
  }

  Future<ShiftSession> openShift({
    required String cashierId,
    required String cashierName,
    required String roleId,
    double openingFloat = 0,
  }) async {
    final response = await http
        .post(
          _posUri('/pos/shifts/open'),
          headers: _headers,
          body: jsonEncode({
            'cashierId': cashierId,
            'cashierName': cashierName,
            'roleId': roleId,
            'openingFloat': openingFloat,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_readError(response, 'فشل فتح الوردية'));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    _activeShift = ShiftSession.fromJson(Map<String, dynamic>.from(decoded));
    _notifySessionChanged();
    return _activeShift!;
  }

  Future<ShiftSession> closeShift({
    required String shiftId,
    required double closingCashCounted,
    String notes = '',
    String? closedById,
    String? closedByName,
    String? cashierId,
    String? cashierName,
    double? openingFloat,
    String? roleId,
    String? managerPin,
    String? pendingCloseReason,
    String? approvalRequestId,
    String? authorizedById,
    String? authorizedByName,
  }) async {
    final response = await http
        .post(
          _posUri('/pos/shifts/${Uri.encodeComponent(shiftId)}/close'),
          headers: _headers,
          body: jsonEncode({
            'closingCashCounted': closingCashCounted,
            'notes': notes,
            if (closedById != null) 'closedById': closedById,
            if (closedByName != null) 'closedByName': closedByName,
            'cashierId': cashierId ?? closedById ?? _activeShift?.cashierId,
            'cashierName': cashierName ?? closedByName ?? _activeShift?.cashierName,
            'openingFloat': openingFloat ?? _activeShift?.openingFloat ?? 0,
            'roleId': roleId ?? _activeShift?.roleId,
            if (managerPin != null && managerPin.trim().isNotEmpty)
              'managerPin': managerPin.trim(),
            if (pendingCloseReason != null && pendingCloseReason.trim().isNotEmpty)
              'pendingCloseReason': pendingCloseReason.trim(),
            if (approvalRequestId != null && approvalRequestId.trim().isNotEmpty)
              'approvalRequestId': approvalRequestId.trim(),
            if (authorizedById != null) 'authorizedById': authorizedById,
            if (authorizedByName != null) 'authorizedByName': authorizedByName,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل إغلاق الوردية'));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    final closed = ShiftSession.fromJson(Map<String, dynamic>.from(decoded));
    if (_activeShift?.id == closed.id) {
      _activeShift = null;
      _notifySessionChanged();
    }
    return closed;
  }

  Future<ShiftReportsResult> fetchShiftReports({
    String? restaurantId,
    String? cashierId,
    DateTime? from,
    DateTime? to,
    bool includeOpen = true,
  }) async {
    final scopedRestaurantId =
        restaurantId?.trim().isNotEmpty == true
            ? restaurantId!.trim()
            : SuperAdminScopeService.instance.effectiveRestaurantId;

    final response = await http
        .get(
          _posUri(
            '/pos/shifts',
            query: {
              if (scopedRestaurantId.isNotEmpty) 'restaurant_id': scopedRestaurantId,
              if (cashierId != null && cashierId.isNotEmpty) 'cashierId': cashierId,
              if (from != null) 'from': from.toUtc().toIso8601String(),
              if (to != null) 'to': to.toUtc().toIso8601String(),
              'includeOpen': includeOpen ? 'true' : 'false',
            },
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 400) {
      throw Exception(_readError(response, 'معرّف المطعم مطلوب'));
    }
    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل تحميل تقارير الورديات'));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      final shifts = decoded
          .whereType<Map>()
          .map((row) => ShiftSession.fromJson(Map<String, dynamic>.from(row)))
          .toList();
      return ShiftReportsResult(shifts: shifts);
    }
    if (decoded is! Map) {
      return const ShiftReportsResult(shifts: []);
    }

    final map = Map<String, dynamic>.from(decoded);
    final rawShifts = map['shifts'];
    final shifts = rawShifts is List
        ? rawShifts
            .whereType<Map>()
            .map((row) => ShiftSession.fromJson(Map<String, dynamic>.from(row)))
            .toList()
        : <ShiftSession>[];
    final meta = map['meta'] is Map
        ? ShiftReportsMeta.fromJson(Map<String, dynamic>.from(map['meta'] as Map))
        : const ShiftReportsMeta();

    return ShiftReportsResult(shifts: shifts, meta: meta);
  }

  Future<List<StaffUser>> fetchStaffUsers({bool allRestaurants = false}) async {
    final response = await http
        .get(
          _posUri(
            '/pos/staff',
            query: allRestaurants ? {'all': '1'} : null,
            scoped: !allRestaurants,
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل تحميل الموظفين'));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((row) => StaffUser.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<StaffUser> createStaffUser({
    required String name,
    required String roleId,
    required String pin,
    String? employeeId,
    bool hrProvision = false,
  }) async {
    final headers = Map<String, String>.from(_headers);
    if (hrProvision) {
      headers['X-Staff-Provision-Source'] = 'hr';
    }
    final response = await http
        .post(
          _posUri('/pos/staff'),
          headers: headers,
          body: jsonEncode({
            'name': name,
            'roleId': roleId,
            'pin': pin,
            if (employeeId != null && employeeId.isNotEmpty) 'employeeId': employeeId,
            if (hrProvision) 'provisionSource': 'hr',
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_readError(response, 'فشل إضافة الموظف'));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    return StaffUser.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<StaffUser> updateStaffUser(
    String id, {
    String? name,
    String? roleId,
    String? pin,
    bool? isActive,
    String? employeeId,
    bool hrProvision = false,
  }) async {
    final headers = Map<String, String>.from(_headers);
    if (hrProvision) {
      headers['X-Staff-Provision-Source'] = 'hr';
    }
    final response = await http
        .patch(
          _posUri('/pos/staff/$id'),
          headers: headers,
          body: jsonEncode({
            if (name != null) 'name': name,
            if (roleId != null) 'roleId': roleId,
            if (pin != null) 'pin': pin,
            if (isActive != null) 'isActive': isActive,
            if (employeeId != null) 'employeeId': employeeId,
            if (hrProvision) 'provisionSource': 'hr',
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل تحديث الموظف'));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    return StaffUser.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<PosApprovalRequest> createApprovalRequest({
    required String type,
    required String reason,
    required String shiftId,
    Map<String, dynamic>? payload,
    String? requestedById,
    String? requestedByName,
  }) async {
    final response = await http
        .post(
          _posUri('/pos/approvals'),
          headers: _headers,
          body: jsonEncode({
            'type': type,
            'reason': reason,
            'shiftId': shiftId,
            if (payload != null) 'payload': payload,
            if (requestedById != null) 'requestedById': requestedById,
            if (requestedByName != null) 'requestedByName': requestedByName,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_readError(response, 'فشل إرسال طلب الموافقة'));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    final raw = decoded['request'];
  if (raw is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    return PosApprovalRequest.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<PosApprovalRequest> fetchApprovalRequest(String id) async {
    final response = await http
        .get(
          _posUri('/pos/approvals/${Uri.encodeComponent(id)}'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل تحميل طلب الموافقة'));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    final raw = decoded['request'];
    if (raw is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    return PosApprovalRequest.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<List<PosApprovalRequest>> fetchApprovalRequests({
    String status = 'PENDING',
    int limit = 50,
    String? roleId,
  }) async {
    final response = await http
        .get(
          _posUri(
            '/pos/approvals',
            query: {
              'status': status,
              'limit': '$limit',
              if (roleId != null && roleId.isNotEmpty) 'roleId': roleId,
            },
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل تحميل طلبات الموافقة'));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return const [];
    final rows = decoded['requests'];
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map)
          PosApprovalRequest.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  Future<PosApprovalRequest> approveApprovalRequest(
    String id, {
    String? reviewNote,
    String? reviewedById,
    String? reviewedByName,
    String? roleId,
  }) async {
    return _reviewApprovalRequest(
      id,
      action: 'approve',
      reviewNote: reviewNote,
      reviewedById: reviewedById,
      reviewedByName: reviewedByName,
      roleId: roleId,
    );
  }

  Future<PosApprovalRequest> rejectApprovalRequest(
    String id, {
    String? reviewNote,
    String? reviewedById,
    String? reviewedByName,
    String? roleId,
  }) async {
    return _reviewApprovalRequest(
      id,
      action: 'reject',
      reviewNote: reviewNote,
      reviewedById: reviewedById,
      reviewedByName: reviewedByName,
      roleId: roleId,
    );
  }

  Future<PosApprovalRequest> cancelApprovalRequest(String id) async {
    final response = await http
        .post(
          _posUri('/pos/approvals/${Uri.encodeComponent(id)}/cancel'),
          headers: _headers,
          body: jsonEncode({}),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل إلغاء طلب الموافقة'));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    final raw = decoded['request'];
    if (raw is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    return PosApprovalRequest.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<PosApprovalRequest> _reviewApprovalRequest(
    String id, {
    required String action,
    String? reviewNote,
    String? reviewedById,
    String? reviewedByName,
    String? roleId,
  }) async {
    final response = await http
        .post(
          _posUri('/pos/approvals/${Uri.encodeComponent(id)}/$action'),
          headers: _headers,
          body: jsonEncode({
            if (reviewNote != null) 'reviewNote': reviewNote,
            if (reviewedById != null) 'reviewedById': reviewedById,
            if (reviewedByName != null) 'reviewedByName': reviewedByName,
            if (roleId != null) 'roleId': roleId,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل مراجعة طلب الموافقة'));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    final raw = decoded['request'];
    if (raw is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    return PosApprovalRequest.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<({List<KitchenVoidLiability> liabilities, KitchenVoidLiabilitySummary summary})>
      fetchKitchenVoidLiabilities({
    String? shiftId,
    String? cashierId,
    String status = 'ALL',
  }) async {
    final response = await http
        .get(
          _posUri(
            '/pos/kitchen-void-liabilities',
            query: {
              if (shiftId != null && shiftId.isNotEmpty) 'shiftId': shiftId,
              if (cashierId != null && cashierId.isNotEmpty) 'cashierId': cashierId,
              'status': status,
            },
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل تحميل مسؤوليات إلغاء المطبخ'));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      return (
        liabilities: const <KitchenVoidLiability>[],
        summary: const KitchenVoidLiabilitySummary(),
      );
    }
    final rows = decoded['liabilities'];
    final summaryRaw = decoded['summary'];
    final liabilities = rows is List
        ? [
            for (final row in rows)
              if (row is Map)
                KitchenVoidLiability.fromJson(Map<String, dynamic>.from(row)),
          ]
        : <KitchenVoidLiability>[];
    final summary = summaryRaw is Map
        ? KitchenVoidLiabilitySummary.fromJson(Map<String, dynamic>.from(summaryRaw))
        : const KitchenVoidLiabilitySummary();
    return (liabilities: liabilities, summary: summary);
  }

  Future<KitchenVoidLiability> reviewKitchenVoidLiability(
    String id, {
    required bool approve,
    String? reviewNote,
    String? reviewedById,
    String? reviewedByName,
    String? roleId,
  }) async {
    final action = approve ? 'approve' : 'reject';
    final response = await http
        .post(
          _posUri('/pos/kitchen-void-liabilities/${Uri.encodeComponent(id)}/$action'),
          headers: _headers,
          body: jsonEncode({
            if (reviewNote != null) 'reviewNote': reviewNote,
            if (reviewedById != null) 'reviewedById': reviewedById,
            if (reviewedByName != null) 'reviewedByName': reviewedByName,
            if (roleId != null) 'roleId': roleId,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل مراجعة مسؤولية الإلغاء'));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    final raw = decoded['liability'];
    if (raw is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    return KitchenVoidLiability.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<void> applyKitchenVoidPayrollDeductions({
    required int month,
    required int year,
    required List<String> liabilityIds,
  }) async {
    if (liabilityIds.isEmpty) return;
    final response = await http
        .post(
          _posUri('/pos/kitchen-void-liabilities/apply-payroll'),
          headers: _headers,
          body: jsonEncode({
            'month': month,
            'year': year,
            'liabilityIds': liabilityIds,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل تسجيل خصم مديونية المطبخ'));
    }
  }

  bool canReviewRemoteApprovals() {
    final roleId =
        (cashierSession?.roleId ?? activeShift?.roleId ?? '').toLowerCase();
    return roleId == 'manager' ||
        roleId == 'shift_supervisor' ||
        roleId == 'pos_admin' ||
        AdminAuthService.instance.isRestaurantAdmin ||
        AdminAuthService.instance.isSuperAdmin;
  }

  Future<void> voidOrder({
    required String orderId,
    required String reason,
    String? performedById,
    String? performedByName,
    String? managerPin,
    String? authorizedById,
    String? authorizedByName,
  }) async {
    final response = await http
        .patch(
          Uri.parse('${ApiService.baseUrl}/orders/$orderId/void').replace(
            queryParameters: {
              if (SuperAdminScopeService.instance.effectiveRestaurantId.isNotEmpty)
                'restaurant_id': SuperAdminScopeService.instance.effectiveRestaurantId,
            },
          ),
          headers: _headers,
          body: jsonEncode({
            'reason': reason,
            if (performedById != null) 'performedById': performedById,
            if (performedByName != null) 'performedByName': performedByName,
            if (managerPin != null) 'managerPin': managerPin,
            if (authorizedById != null) 'authorizedById': authorizedById,
            if (authorizedByName != null) 'authorizedByName': authorizedByName,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل إلغاء الطلب'));
    }
  }

  String _readError(http.Response response, String fallback) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {}
    if (kDebugMode) {
      debugPrint('POS API error ${response.statusCode}: ${response.body}');
    }
    return '$fallback (${response.statusCode})';
  }

  Future<void> bootstrapAdminCashier({Map<String, bool>? permissions}) async {
    if (_cashierSession != null && permissions == null) return;
    final adminName = AdminAuthService.instance.restaurantName ?? 'مدير';
    applyCashierSession(
      PosCashierSession(
        staff: StaffUser(
          id: 'restaurant_admin',
          name: adminName,
          roleId: 'pos_admin',
        ),
        roleId: 'pos_admin',
        permissions: permissions ?? PosPermissionCatalog.fullAccessMap(),
      ),
    );
  }
}
