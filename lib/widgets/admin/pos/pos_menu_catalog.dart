import 'package:flutter/material.dart';

import '../../models/pos_role.dart';
import '../../services/pos_operations_service.dart';

/// POS sub-routes (synced with `/admin/pos/...` on web).
enum PosRoute {
  home('/admin/pos'),
  shiftClose('/admin/pos/shift-close'),
  reports('/admin/pos/reports'),
  voidOrders('/admin/pos/void-orders'),
  staff('/admin/pos/staff'),
  menu('/admin/pos/menu');

  const PosRoute(this.path);

  final String path;

  static PosRoute fromPath(String? raw) {
    final normalized = (raw ?? '').trim();
    if (normalized.isEmpty || normalized == '/admin/pos') {
      return PosRoute.home;
    }
    for (final route in PosRoute.values) {
      if (route.path == normalized) return route;
    }
    return PosRoute.home;
  }
}

enum PosSidebarAction {
  navigate,
  openShiftCloseModal,
}

class PosSidebarMenuItem {
  const PosSidebarMenuItem({
    required this.id,
    required this.icon,
    required this.label,
    required this.requiredPermission,
    required this.route,
    this.action = PosSidebarAction.navigate,
  });

  final String id;
  final IconData icon;
  final String label;
  final String requiredPermission;
  final PosRoute route;
  final PosSidebarAction action;
}

/// Maps cashier permissions to POS sidebar entries.
abstract final class PosMenuCatalog {
  static const allItems = <PosSidebarMenuItem>[
    PosSidebarMenuItem(
      id: 'pos_home',
      icon: Icons.point_of_sale,
      label: 'نقطة البيع / تسجيل الطلبات',
      requiredPermission: PosPermissionKeys.posAccess,
      route: PosRoute.home,
    ),
    PosSidebarMenuItem(
      id: 'close_shift',
      icon: Icons.lock_clock,
      label: 'إغلاق الوردية',
      requiredPermission: PosPermissionKeys.closeShift,
      route: PosRoute.shiftClose,
      action: PosSidebarAction.openShiftCloseModal,
    ),
    PosSidebarMenuItem(
      id: 'shift_reports',
      icon: Icons.receipt_long_outlined,
      label: 'تقارير الوردية',
      requiredPermission: PosPermissionKeys.viewShiftReports,
      route: PosRoute.reports,
    ),
    PosSidebarMenuItem(
      id: 'void_orders',
      icon: Icons.cancel_outlined,
      label: 'إلغاء الطلبات (Void)',
      requiredPermission: PosPermissionKeys.voidOrders,
      route: PosRoute.voidOrders,
    ),
    PosSidebarMenuItem(
      id: 'manage_staff',
      icon: Icons.groups_outlined,
      label: 'إدارة الموظفين / إضافة كاشير',
      requiredPermission: PosPermissionKeys.manageStaff,
      route: PosRoute.staff,
    ),
    PosSidebarMenuItem(
      id: 'manage_menu',
      icon: Icons.restaurant_menu,
      label: 'إدارة المنيو والأصناف',
      requiredPermission: PosPermissionKeys.manageMenu,
      route: PosRoute.menu,
    ),
  ];

  static List<PosSidebarMenuItem> visibleItems() {
    final pos = PosOperationsService.instance;
    return allItems.where((item) {
      if (item.requiredPermission == PosPermissionKeys.posAccess) {
        return pos.allows(PosPermissionKeys.posAccess) ||
            pos.allows(PosPermissionKeys.processOrders);
      }
      return pos.allows(item.requiredPermission);
    }).toList(growable: false);
  }
}
