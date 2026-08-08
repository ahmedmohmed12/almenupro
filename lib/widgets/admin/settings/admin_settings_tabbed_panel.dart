import 'package:flutter/material.dart';

import '../../../services/super_admin_scope_service.dart';
import '../../../utils/admin_settings_url.dart';
import '../admin_breakpoints.dart';
import '../admin_loyalty_settings_card.dart';
import '../admin_payment_settings_card.dart';
import '../admin_platform_settings_card.dart';
import '../admin_pos_roles_staff_card.dart';
import '../admin_responsive_layout.dart';
import '../admin_sound_settings_card.dart';
import '../admin_store_profile_card.dart';
import '../admin_working_hours_card.dart';
import 'admin_email_notifications_card.dart';
import 'admin_settings_tab.dart';
import 'admin_whatsapp_settings_section.dart';

class AdminSettingsTabbedPanel extends StatefulWidget {
  const AdminSettingsTabbedPanel({
    super.key,
    required this.isSuperAdmin,
    this.restaurantLabel,
  });

  final bool isSuperAdmin;
  final String? restaurantLabel;

  @override
  State<AdminSettingsTabbedPanel> createState() =>
      _AdminSettingsTabbedPanelState();
}

class _AdminSettingsTabbedPanelState extends State<AdminSettingsTabbedPanel> {
  static const burgundy = Color(0xFF6B1124);

  late AdminSettingsTab _activeTab;

  @override
  void initState() {
    super.initState();
    _activeTab = readSettingsTabFromUrl();
  }

  void _selectTab(AdminSettingsTab tab) {
    if (_activeTab == tab) return;
    setState(() => _activeTab = tab);
    writeSettingsTabToUrl(tab);
  }

  IconData _iconFor(AdminSettingsTab tab) {
    switch (tab) {
      case AdminSettingsTab.whatsapp:
        return Icons.chat_bubble_outline;
      case AdminSettingsTab.store:
        return Icons.storefront_outlined;
      case AdminSettingsTab.loyalty:
        return Icons.card_giftcard_outlined;
      case AdminSettingsTab.email:
        return Icons.mail_outline;
    }
  }

  Widget _buildTabButton(AdminSettingsTab tab) {
    final selected = _activeTab == tab;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectTab(tab),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? burgundy : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? burgundy : Colors.grey.shade300,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: burgundy.withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _iconFor(tab),
                size: 18,
                color: selected ? Colors.white : burgundy,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  tab.labelAr,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.grey.shade800,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTabContent() {
    switch (_activeTab) {
      case AdminSettingsTab.whatsapp:
        return const AdminWhatsappSettingsSection();
      case AdminSettingsTab.store:
        return const AdminStoreProfileCard();
      case AdminSettingsTab.loyalty:
        return const AdminLoyaltySettingsCard();
      case AdminSettingsTab.email:
        return const AdminEmailNotificationsCard();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = SuperAdminScopeService.instance;
    final restaurantLabel = widget.isSuperAdmin
        ? (scope.selectedRestaurantName ?? '—')
        : (widget.restaurantLabel ?? 'المطعm');

    return AdminResponsivePage(
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'إعدادات المحل',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: burgundy,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.isSuperAdmin
                ? 'المطعم الحالي: $restaurantLabel'
                : 'اضبط إعدادات محلّك من التبويبات أدناه',
          ),
          if (widget.isSuperAdmin && !scope.hasSelection) ...[
            const SizedBox(height: 12),
            const Text(
              'اختر مطعماً من قائمة «المطاعm» أولاً.',
              style: TextStyle(color: Colors.orange),
            ),
          ],
          const SizedBox(height: 20),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AdminSettingsTab.values.map(_buildTabButton).toList(),
            ),
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: KeyedSubtree(
              key: ValueKey(_activeTab.id),
              child: _buildActiveTabContent(),
            ),
          ),
          const SizedBox(height: 24),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: false,
            title: const Text(
              '⚙️ إعدادات إضافية (الدفع، POS، ساعات العمل)',
              style: TextStyle(fontWeight: FontWeight.w600, color: burgundy),
            ),
            children: const [
              SizedBox(height: 8),
              AdminPaymentSettingsCard(),
              SizedBox(height: 16),
              AdminPlatformSettingsCard(),
              SizedBox(height: 16),
              AdminPosRolesStaffCard(),
              SizedBox(height: 16),
              AdminWorkingHoursCard(),
              SizedBox(height: 8),
              if (!widget.isSuperAdmin) ...[
                AdminSoundSettingsCard(),
                SizedBox(height: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
