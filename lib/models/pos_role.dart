import 'pos_permission_catalog.dart';

class PosPermissionKeys {
  PosPermissionKeys._();

  static const posAccess = 'pos_access';
  static const processOrders = 'process_orders';
  static const printInvoice = 'print_invoice';
  static const openCashDrawer = 'open_cash_drawer';
  static const overridePrices = 'override_prices';
  static const applyManualDiscount = 'apply_manual_discount';
  static const applyDiscounts = 'apply_discounts';
  static const voidOrders = 'void_orders';
  static const processRefunds = 'process_refunds';
  static const viewDailySales = 'view_daily_sales';
  static const viewShiftReports = 'view_shift_reports';
  static const viewReports = 'view_reports';
  static const manageMenu = 'manage_menu';
  static const manageSettings = 'manage_settings';
  static const manageStaff = 'manage_staff';
  static const closeShift = 'close_shift';
  static const managerOverride = 'manager_override';
}

class PosRole {
  const PosRole({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.permissions,
    this.isBuiltIn = false,
  });

  final String id;
  final String nameAr;
  final String nameEn;
  final Map<String, bool> permissions;
  final bool isBuiltIn;

  bool allows(String permission) =>
      PosPermissionCatalog.roleAllows(permissions, permission);

  factory PosRole.fromJson(Map<String, dynamic> json) {
    final rawPermissions = json['permissions'];
    final permissions = <String, bool>{};
    if (rawPermissions is Map) {
      rawPermissions.forEach((key, value) {
        permissions[key.toString()] = value == true;
      });
    }
    return PosRole(
      id: json['id']?.toString() ?? '',
      nameAr: json['nameAr']?.toString() ?? json['name_ar']?.toString() ?? '',
      nameEn: json['nameEn']?.toString() ?? json['name_en']?.toString() ?? '',
      permissions: PosPermissionCatalog.normalizePermissions(permissions),
      isBuiltIn: json['isBuiltIn'] == true || json['is_built_in'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nameAr': nameAr,
        'nameEn': nameEn,
        'isBuiltIn': isBuiltIn,
        'permissions': PosPermissionCatalog.normalizePermissions(permissions),
      };

  PosRole copyWith({
    String? id,
    String? nameAr,
    String? nameEn,
    Map<String, bool>? permissions,
    bool? isBuiltIn,
  }) {
    return PosRole(
      id: id ?? this.id,
      nameAr: nameAr ?? this.nameAr,
      nameEn: nameEn ?? this.nameEn,
      permissions: permissions ?? this.permissions,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    );
  }

  static List<PosRole> defaults() => [
        PosRole(
          id: 'cashier',
          nameAr: 'كاشير',
          nameEn: 'Cashier',
          isBuiltIn: true,
          permissions: PosPermissionCatalog.normalizePermissions({
            PosPermissionKeys.posAccess: true,
            PosPermissionKeys.processOrders: true,
            PosPermissionKeys.printInvoice: true,
            PosPermissionKeys.viewShiftReports: true,
            PosPermissionKeys.viewReports: true,
            PosPermissionKeys.closeShift: true,
          }),
        ),
        PosRole(
          id: 'shift_supervisor',
          nameAr: 'مشرف وردية',
          nameEn: 'Shift Supervisor',
          isBuiltIn: true,
          permissions: PosPermissionCatalog.normalizePermissions({
            PosPermissionKeys.posAccess: true,
            PosPermissionKeys.processOrders: true,
            PosPermissionKeys.printInvoice: true,
            PosPermissionKeys.openCashDrawer: true,
            PosPermissionKeys.overridePrices: true,
            PosPermissionKeys.applyManualDiscount: true,
            PosPermissionKeys.applyDiscounts: true,
            PosPermissionKeys.voidOrders: true,
            PosPermissionKeys.processRefunds: true,
            PosPermissionKeys.viewDailySales: true,
            PosPermissionKeys.viewShiftReports: true,
            PosPermissionKeys.viewReports: true,
            PosPermissionKeys.closeShift: true,
            PosPermissionKeys.managerOverride: true,
          }),
        ),
        PosRole(
          id: 'pos_admin',
          nameAr: 'مدير POS',
          nameEn: 'POS Admin',
          isBuiltIn: true,
          permissions: PosPermissionCatalog.fullAccessMap(),
        ),
      ];
}
