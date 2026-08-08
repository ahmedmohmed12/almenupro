import 'pos_role.dart';

enum PosPermissionCategory {
  pos,
  orders,
  staff,
  system,
}

class PosPermissionDefinition {
  const PosPermissionDefinition({
    required this.key,
    required this.labelAr,
    required this.category,
  });

  final String key;
  final String labelAr;
  final PosPermissionCategory category;
}

/// Single source of truth for every controllable permission in Menu Pro.
class PosPermissionCatalog {
  PosPermissionCatalog._();

  static const categoryLabels = {
    PosPermissionCategory.pos: '🛒 صلاحيات نقطة البيع (POS)',
    PosPermissionCategory.orders: '📦 صلاحيات الطلبات والمبيعات',
    PosPermissionCategory.staff: '👥 إدارة الموظفين والكاشير',
    PosPermissionCategory.system: '⚙️ إعدادات النظام والتقارير',
  };

  static const all = <PosPermissionDefinition>[
    PosPermissionDefinition(
      key: PosPermissionKeys.posAccess,
      labelAr: 'الوصول لشاشة POS',
      category: PosPermissionCategory.pos,
    ),
    PosPermissionDefinition(
      key: PosPermissionKeys.processOrders,
      labelAr: 'تسجيل ومعالجة الطلبات',
      category: PosPermissionCategory.pos,
    ),
    PosPermissionDefinition(
      key: PosPermissionKeys.printInvoice,
      labelAr: 'طباعة الفواتير',
      category: PosPermissionCategory.pos,
    ),
    PosPermissionDefinition(
      key: PosPermissionKeys.openCashDrawer,
      labelAr: 'فتح درج النقدية',
      category: PosPermissionCategory.pos,
    ),
    PosPermissionDefinition(
      key: PosPermissionKeys.overridePrices,
      labelAr: 'تعديل أسعار المنتجات في POS',
      category: PosPermissionCategory.pos,
    ),
    PosPermissionDefinition(
      key: PosPermissionKeys.applyManualDiscount,
      labelAr: 'إضافة خصم يدوي',
      category: PosPermissionCategory.pos,
    ),
    PosPermissionDefinition(
      key: PosPermissionKeys.applyDiscounts,
      labelAr: 'تطبيق خصومات عامة',
      category: PosPermissionCategory.pos,
    ),
    PosPermissionDefinition(
      key: PosPermissionKeys.closeShift,
      labelAr: 'إغلاق الوردية',
      category: PosPermissionCategory.pos,
    ),
    PosPermissionDefinition(
      key: PosPermissionKeys.voidOrders,
      labelAr: 'إلغاء الطلبات (Void)',
      category: PosPermissionCategory.orders,
    ),
    PosPermissionDefinition(
      key: PosPermissionKeys.processRefunds,
      labelAr: 'معالجة المرتجعات',
      category: PosPermissionCategory.orders,
    ),
    PosPermissionDefinition(
      key: PosPermissionKeys.manageStaff,
      labelAr: 'إضافة / تعديل الكاشير والموظفين',
      category: PosPermissionCategory.staff,
    ),
    PosPermissionDefinition(
      key: PosPermissionKeys.viewReports,
      labelAr: 'عرض التقارير والورديات',
      category: PosPermissionCategory.system,
    ),
    PosPermissionDefinition(
      key: PosPermissionKeys.viewDailySales,
      labelAr: 'عرض مبيعات اليوم',
      category: PosPermissionCategory.system,
    ),
    PosPermissionDefinition(
      key: PosPermissionKeys.viewShiftReports,
      labelAr: 'عرض تقارير إغلاق الوردية',
      category: PosPermissionCategory.system,
    ),
    PosPermissionDefinition(
      key: PosPermissionKeys.manageMenu,
      labelAr: 'إدارة المنيو',
      category: PosPermissionCategory.system,
    ),
    PosPermissionDefinition(
      key: PosPermissionKeys.manageSettings,
      labelAr: 'إعدادات النظام',
      category: PosPermissionCategory.system,
    ),
    PosPermissionDefinition(
      key: PosPermissionKeys.managerOverride,
      labelAr: 'تفويض المشرف (Manager Override)',
      category: PosPermissionCategory.system,
    ),
  ];

  static List<String> get allKeys =>
      all.map((entry) => entry.key).toList(growable: false);

  static List<PosPermissionDefinition> forCategory(PosPermissionCategory category) {
    return all.where((entry) => entry.category == category).toList();
  }

  static Map<String, bool> fullAccessMap({bool enabled = true}) {
    return {for (final key in allKeys) key: enabled};
  }

  static Map<String, bool> normalizePermissions(Map<String, bool>? raw) {
    final normalized = <String, bool>{};
    for (final key in allKeys) {
      normalized[key] = raw?[key] == true;
    }
    if (raw != null) {
      raw.forEach((key, value) {
        if (!allKeys.contains(key)) {
          normalized[key] = value == true;
        }
      });
    }
    return normalized;
  }

  static bool roleAllows(Map<String, bool> permissions, String permission) {
    if (permissions[permission] == true) return true;
    if (permission == PosPermissionKeys.applyManualDiscount) {
      return permissions[PosPermissionKeys.applyDiscounts] == true;
    }
    if (permission == PosPermissionKeys.viewReports) {
      return permissions[PosPermissionKeys.viewShiftReports] == true ||
          permissions[PosPermissionKeys.viewDailySales] == true;
    }
    return false;
  }
}
