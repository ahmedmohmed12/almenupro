import 'package:flutter/material.dart';

import '../../../services/super_admin_scope_service.dart';
import '../admin_breakpoints.dart';
import '../admin_loyalty_settings_card.dart';
import '../admin_menu_engineering_settings_card.dart';
import '../admin_payment_settings_card.dart';
import '../admin_platform_settings_card.dart';
import '../admin_pos_roles_staff_card.dart';
import '../admin_responsive_layout.dart';
import '../admin_sound_settings_card.dart';
import '../admin_store_profile_card.dart';
import '../admin_working_hours_card.dart';
import 'admin_email_notifications_card.dart';
import 'admin_link_hub_panel.dart';
import 'admin_printer_settings_card.dart';
import 'admin_settings_tab.dart';
import 'admin_whatsapp_settings_section.dart';

class AdminSettingsTabbedPanel extends StatelessWidget {
  const AdminSettingsTabbedPanel({
    super.key,
    required this.isSuperAdmin,
    this.restaurantLabel,
    this.activeTab,
  });

  final bool isSuperAdmin;
  final String? restaurantLabel;
  final AdminSettingsTab? activeTab;

  static const burgundy = Color(0xFF6B1124);

  AdminSettingsTab get _tab => activeTab ?? AdminSettingsTab.whatsapp;

  Widget _buildActiveTabContent() {
    switch (_tab) {
      case AdminSettingsTab.whatsapp:
        return const AdminWhatsappSettingsSection();
      case AdminSettingsTab.store:
        return const AdminStoreProfileCard();
      case AdminSettingsTab.linkHub:
        return const AdminLinkHubPanel();
      case AdminSettingsTab.menuEngineering:
        return const AdminMenuEngineeringSettingsCard();
      case AdminSettingsTab.loyalty:
        return const AdminLoyaltySettingsCard();
      case AdminSettingsTab.email:
        return const AdminEmailNotificationsCard();
      case AdminSettingsTab.platforms:
        return const AdminPlatformSettingsCard();
      case AdminSettingsTab.paymentMethods:
        return const AdminPaymentSettingsCard();
      case AdminSettingsTab.roles:
        return const AdminPosRolesStaffCard();
      case AdminSettingsTab.workingHours:
        return const AdminWorkingHoursCard();
      case AdminSettingsTab.audioNotifications:
        return const AdminSoundSettingsCard();
      case AdminSettingsTab.printer:
        return const AdminPrinterSettingsCard();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = SuperAdminScopeService.instance;
    final label = isSuperAdmin
        ? (scope.selectedRestaurantName ?? '—')
        : (restaurantLabel ?? 'المطعم');
    final pagePad = AdminBreakpoints.pagePadding(context);

    return AdminResponsivePage(
      scrollable: true,
      padding: EdgeInsets.fromLTRB(pagePad, 8, pagePad, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tab.labelAr,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: burgundy,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            isSuperAdmin
                ? 'المطعم الحالي: $label'
                : 'عدّل هذه الإعدادات من القائمة الجانبية',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          if (isSuperAdmin && !scope.hasSelection) ...[
            const SizedBox(height: 8),
            const Text(
              'اختر مطعماً من قائمة «المطاعم» أولاً.',
              style: TextStyle(color: Colors.orange),
            ),
          ],
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: KeyedSubtree(
              key: ValueKey(_tab.id),
              child: _buildActiveTabContent(),
            ),
          ),
        ],
      ),
    );
  }
}
