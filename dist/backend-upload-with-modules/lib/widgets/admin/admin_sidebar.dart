import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_strings.dart';
import '../language_toggle_button.dart';
import 'settings/admin_settings_tab.dart';

class AdminSidebarItem {
  const AdminSidebarItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// Default admin navigation — live dashboard first, then POS and operations.
class AdminSidebar extends StatefulWidget {
  const AdminSidebar({
    super.key,
    this.items = defaultItems,
    required this.selectedIndex,
    required this.onItemSelected,
    this.width = expandedWidth,
    this.enableCollapse = true,
    this.footerBuilder,
    this.settingsNavIndex,
    this.selectedSettingsTab,
    this.onSettingsSubItemSelected,
    this.isSuperAdmin = false,
    this.onLogout,
  });

  static const double expandedWidth = 260;
  static const double collapsedWidth = 76;

  static const int analyticsIndex = 0;
  static const int posIndex = 1;
  static const int ordersIndex = 2;
  static const int customersIndex = 3;
  static const int menuIndex = 4;
  static const int deliveryZonesIndex = 5;
  static const int offersIndex = 6;
  static const int smartUpsellIndex = 7;
  static const int staffIndex = 8;
  static const int reviewsIndex = 9;
  static const int expensesIndex = 10;
  static const int settingsIndex = 11;
  static const int tablesIndex = 12;

  /// Super Admin sidebar — live dashboard first, then POS and restaurants.
  static const int superAnalyticsIndex = 0;
  static const int superPosIndex = 1;
  static const int superMenuIndex = 2;
  static const int superRestaurantsIndex = 3;
  static const int superDeliveryZonesIndex = 4;
  static const int superDriversIndex = 5;
  static const int superOffersIndex = 6;
  static const int superSmartUpsellIndex = 7;
  static const int superStaffIndex = 8;
  static const int superReviewsIndex = 9;
  static const int superExpensesIndex = 10;
  static const int superSettingsIndex = 11;
  static const int superTablesIndex = 12;

  static const AdminSidebarItem tablesItem = AdminSidebarItem(
    icon: Icons.table_restaurant,
    label: 'إدارة الطاولات',
  );

  static const List<AdminSidebarItem> defaultItems = [
    AdminSidebarItem(icon: Icons.dashboard_outlined, label: 'لوحة المتابعة'),
    AdminSidebarItem(icon: Icons.point_of_sale, label: 'نقطة البيع POS'),
    AdminSidebarItem(icon: Icons.receipt_long_outlined, label: 'الطلبات'),
    AdminSidebarItem(icon: Icons.people_outline, label: 'العملاء'),
    AdminSidebarItem(
      icon: Icons.restaurant_menu,
      label: 'إدارة المنيو والأصناف',
    ),
    AdminSidebarItem(
      icon: Icons.local_shipping_outlined,
      label: 'مناطق التوصيل ورسومها',
    ),
    AdminSidebarItem(
      icon: Icons.local_offer_outlined,
      label: 'العروض والخصومات',
    ),
    AdminSidebarItem(icon: Icons.auto_awesome, label: 'البياع الشاطر'),
    AdminSidebarItem(icon: Icons.badge_outlined, label: 'الموظفين والكاشير'),
    AdminSidebarItem(
      icon: Icons.star_rate_rounded,
      label: 'التقييمات والمراجعات',
    ),
    AdminSidebarItem(
      icon: Icons.account_balance_wallet_outlined,
      label: 'إدارة المصاريف',
    ),
    AdminSidebarItem(icon: Icons.store, label: 'إعدادات المحل والواتساب'),
  ];

  static const List<AdminSidebarItem> cashierItems = [
    AdminSidebarItem(icon: Icons.point_of_sale, label: 'نقطة البيع POS'),
  ];

  static const List<AdminSidebarItem> superAdminItems = [
    AdminSidebarItem(icon: Icons.dashboard_outlined, label: 'لوحة المتابعة'),
    AdminSidebarItem(icon: Icons.point_of_sale, label: 'نقطة البيع POS'),
    AdminSidebarItem(
      icon: Icons.restaurant_menu,
      label: 'إدارة المنيو والأصناف',
    ),
    AdminSidebarItem(icon: Icons.apartment, label: 'المطاعم والاستيراد'),
    AdminSidebarItem(
      icon: Icons.local_shipping_outlined,
      label: 'مناطق التوصيل ورسومها',
    ),
    AdminSidebarItem(icon: Icons.delivery_dining, label: 'مركز الأسطول'),
    AdminSidebarItem(
      icon: Icons.local_offer_outlined,
      label: 'العروض والخصومات',
    ),
    AdminSidebarItem(icon: Icons.auto_awesome, label: 'البياع الشاطر'),
    AdminSidebarItem(icon: Icons.badge_outlined, label: 'الموظفين والكاشير'),
    AdminSidebarItem(
      icon: Icons.star_rate_rounded,
      label: 'التقييمات والمراجعات',
    ),
    AdminSidebarItem(
      icon: Icons.account_balance_wallet_outlined,
      label: 'إدارة المصاريف',
    ),
    AdminSidebarItem(icon: Icons.settings, label: 'إعدادات المنصة'),
  ];

  static const Color sidebarBg = Color(0xFF2C353F);
  static const Color activeBg = Color(0xFF6B1124);
  static const Color activeGold = Color(0xFFD49A00);

  static const _collapsedPrefKey = 'admin_sidebar_collapsed';

  final List<AdminSidebarItem> items;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final double width;
  final bool enableCollapse;
  final Widget Function(bool collapsed)? footerBuilder;
  final int? settingsNavIndex;
  final AdminSettingsTab? selectedSettingsTab;
  final ValueChanged<AdminSettingsTab>? onSettingsSubItemSelected;
  final bool isSuperAdmin;
  final VoidCallback? onLogout;

  @override
  State<AdminSidebar> createState() => _AdminSidebarState();
}

class _AdminSidebarState extends State<AdminSidebar> {
  var _collapsed = false;
  var _prefLoaded = false;
  var _settingsExpanded = false;

  @override
  void initState() {
    super.initState();
    _settingsExpanded =
        widget.selectedSettingsTab != null ||
        widget.selectedIndex == widget.settingsNavIndex;
    if (widget.enableCollapse) {
      _loadCollapsedPreference();
    } else {
      _prefLoaded = true;
    }
  }

  @override
  void didUpdateWidget(AdminSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedSettingsTab != null ||
        widget.selectedIndex == widget.settingsNavIndex) {
      _settingsExpanded = true;
    }
  }

  Future<void> _loadCollapsedPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _collapsed = prefs.getBool(AdminSidebar._collapsedPrefKey) ?? false;
      _prefLoaded = true;
    });
  }

  Future<void> _toggleCollapsed() async {
    setState(() => _collapsed = !_collapsed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AdminSidebar._collapsedPrefKey, _collapsed);
  }

  bool get _isCollapsed => widget.enableCollapse && _collapsed;

  double get _effectiveWidth {
    if (!_isCollapsed) return widget.width;
    return AdminSidebar.collapsedWidth;
  }

  List<AdminSettingsTab> get _settingsSubItems =>
      AdminSettingsTab.sidebarItems(isSuperAdmin: widget.isSuperAdmin);

  String _itemLabel(BuildContext context, AdminSidebarItem item) {
    final s = AppStrings.of(context);
    const english = <String, String>{
      'لوحة المتابعة': 'Dashboard',
      'نقطة البيع POS': 'Point of Sale (POS)',
      'الطلبات': 'Orders',
      'العملاء': 'Customers',
      'إدارة المنيو والأصناف': 'Menu & Items',
      'مناطق التوصيل ورسومها': 'Delivery Zones & Fees',
      'العروض والخصومات': 'Offers & Discounts',
      'البياع الشاطر': 'Smart Upselling',
      'الموظفين والكاشير': 'Staff & Cashiers',
      'التقييمات والمراجعات': 'Reviews',
      'إدارة المصاريف': 'Expenses',
      'إعدادات المحل والواتساب': 'Store & WhatsApp Settings',
      'إدارة الطاولات': 'Table Management',
      'المطاعم والاستيراد': 'Restaurants & Import',
      'مركز الأسطول': 'Fleet Center',
      'إعدادات المنصة': 'Platform Settings',
    };
    return s.tr(item.label, english[item.label] ?? item.label);
  }

  String _settingsLabel(BuildContext context, AdminSettingsTab tab) {
    final s = AppStrings.of(context);
    return s.tr(tab.labelAr, switch (tab) {
      AdminSettingsTab.whatsapp => '💬 WhatsApp Number & Integration',
      AdminSettingsTab.store => '🏪 Store Details & Preview',
      AdminSettingsTab.linkHub => '🔗 Link Hub / Link in Bio',
      AdminSettingsTab.menuEngineering => '📈 Dynamic Menu Ordering',
      AdminSettingsTab.loyalty => '🎁 Loyalty & Cashback',
      AdminSettingsTab.email => '✉️ Email Notifications',
      AdminSettingsTab.platforms => '🌐 Platform Settings',
      AdminSettingsTab.paymentMethods => '💳 Payment Methods',
      AdminSettingsTab.roles => '👥 Roles & Permissions',
      AdminSettingsTab.workingHours => '⏰ Working Hours',
      AdminSettingsTab.audioNotifications => '🔔 Sound Notifications',
      AdminSettingsTab.printer => '🖨️ Printer & Invoice Settings',
    });
  }

  bool get _hasSettingsAccordion =>
      widget.settingsNavIndex != null &&
      widget.onSettingsSubItemSelected != null;

  IconData _iconForSettingsTab(AdminSettingsTab tab) {
    switch (tab) {
      case AdminSettingsTab.whatsapp:
        return Icons.chat_bubble_outline;
      case AdminSettingsTab.store:
        return Icons.storefront_outlined;
      case AdminSettingsTab.linkHub:
        return Icons.link_rounded;
      case AdminSettingsTab.menuEngineering:
        return Icons.auto_awesome;
      case AdminSettingsTab.loyalty:
        return Icons.card_giftcard_outlined;
      case AdminSettingsTab.email:
        return Icons.mail_outline;
      case AdminSettingsTab.platforms:
        return Icons.language_outlined;
      case AdminSettingsTab.paymentMethods:
        return Icons.payments_outlined;
      case AdminSettingsTab.roles:
        return Icons.groups_outlined;
      case AdminSettingsTab.workingHours:
        return Icons.schedule_outlined;
      case AdminSettingsTab.audioNotifications:
        return Icons.notifications_active_outlined;
      case AdminSettingsTab.printer:
        return Icons.print_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_prefLoaded && widget.enableCollapse) {
      return SizedBox(
        width: widget.width,
        child: const ColoredBox(
          color: AdminSidebar.sidebarBg,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AdminSidebar.activeGold,
              ),
            ),
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      width: _effectiveWidth,
      color: AdminSidebar.sidebarBg,
      clipBehavior: Clip.hardEdge,
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 12),
            Expanded(child: _buildNavList()),
            if (widget.footerBuilder != null)
              widget.footerBuilder!(_isCollapsed),
            LanguageToggleButton(
              compact: _isCollapsed,
              foregroundColor: Colors.white,
            ),
            if (widget.onLogout != null) _buildLogoutButton(),
            if (widget.enableCollapse) _buildCollapseToggle(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      padding: EdgeInsets.symmetric(
        vertical: 28,
        horizontal: _isCollapsed ? 12 : 20,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AdminSidebar.activeGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.restaurant_menu,
              color: AdminSidebar.activeGold,
              size: 28,
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _isCollapsed
                ? const SizedBox.shrink(key: ValueKey('logo-collapsed'))
                : const Padding(
                    key: ValueKey('logo-expanded'),
                    padding: EdgeInsetsDirectional.only(start: 12),
                    child: Text(
                      'Almenupro',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavList() {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: _isCollapsed ? 8 : 12),
      itemCount: widget.items.length,
      itemBuilder: (context, index) {
        if (_hasSettingsAccordion && index == widget.settingsNavIndex) {
          return _buildSettingsAccordion(index);
        }
        return _buildNavItem(index);
      },
    );
  }

  Widget _buildNavItem(int index) {
    final item = widget.items[index];
    final label = _itemLabel(context, item);
    final isActive =
        widget.selectedIndex == index &&
        (widget.settingsNavIndex == null || index != widget.settingsNavIndex);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isActive ? AdminSidebar.activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => widget.onItemSelected(index),
          child: Tooltip(
            message: _isCollapsed ? label : '',
            preferBelow: false,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _isCollapsed ? 0 : 16,
                vertical: 14,
              ),
              child: _isCollapsed
                  ? Center(
                      child: Icon(
                        item.icon,
                        color: isActive
                            ? AdminSidebar.activeGold
                            : Colors.white70,
                        size: 22,
                      ),
                    )
                  : Row(
                      children: [
                        Icon(
                          item.icon,
                          color: isActive
                              ? AdminSidebar.activeGold
                              : Colors.white70,
                          size: 22,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.white70,
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (isActive)
                          Container(
                            width: 4,
                            height: 22,
                            decoration: BoxDecoration(
                              color: AdminSidebar.activeGold,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsAccordion(int index) {
    final item = widget.items[index];
    final label = _itemLabel(context, item);
    final parentActive = widget.selectedIndex == index;
    final activeChild = widget.selectedSettingsTab;
    final parentHighlighted = parentActive || activeChild != null;

    if (_isCollapsed) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: PopupMenuButton<AdminSettingsTab>(
          tooltip: label,
          color: AdminSidebar.sidebarBg,
          onSelected: widget.onSettingsSubItemSelected,
          itemBuilder: (context) => _settingsSubItems
              .map(
                (tab) => PopupMenuItem(
                  value: tab,
                  child: Text(
                    _settingsLabel(context, tab),
                    style: TextStyle(
                      color: tab == activeChild
                          ? AdminSidebar.activeGold
                          : Colors.white,
                      fontWeight: tab == activeChild
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              )
              .toList(),
          child: Material(
            color: parentHighlighted
                ? AdminSidebar.activeBg
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Icon(
                  item.icon,
                  color: parentHighlighted
                      ? AdminSidebar.activeGold
                      : Colors.white70,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: parentHighlighted && activeChild == null
                ? AdminSidebar.activeBg
                : parentHighlighted
                ? AdminSidebar.activeBg.withValues(alpha: 0.55)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() => _settingsExpanded = !_settingsExpanded);
                if (!parentActive) {
                  widget.onItemSelected(index);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      item.icon,
                      color: parentHighlighted
                          ? AdminSidebar.activeGold
                          : Colors.white70,
                      size: 22,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: parentHighlighted
                              ? Colors.white
                              : Colors.white70,
                          fontWeight: parentHighlighted
                              ? FontWeight.bold
                              : FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _settingsExpanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeInOutCubic,
                      child: Icon(
                        Icons.chevron_left,
                        color: parentHighlighted
                            ? AdminSidebar.activeGold
                            : Colors.white54,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: _settingsExpanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      children: _settingsSubItems
                          .map((tab) => _buildSettingsSubItem(tab))
                          .toList(),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSubItem(AdminSettingsTab tab) {
    final isActive = widget.selectedSettingsTab == tab;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isActive
            ? AdminSidebar.activeBg
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => widget.onSettingsSubItemSelected?.call(tab),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 20,
              end: 12,
              top: 10,
              bottom: 10,
            ),
            child: Row(
              children: [
                Icon(
                  _iconForSettingsTab(tab),
                  size: 18,
                  color: isActive ? AdminSidebar.activeGold : Colors.white60,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _settingsLabel(context, tab),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.white70,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                ),
                if (isActive)
                  Container(
                    width: 3,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AdminSidebar.activeGold,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    final s = AppStrings.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _isCollapsed ? 8 : 12,
        8,
        _isCollapsed ? 8 : 12,
        8,
      ),
      child: Material(
        color: const Color(0xFF6B1124),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.onLogout,
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: 12,
              horizontal: _isCollapsed ? 8 : 12,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.logout, color: Colors.white, size: 20),
                if (!_isCollapsed) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      s.tr('تسجيل الخروج', 'Log out'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapseToggle() {
    final s = AppStrings.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _isCollapsed ? 8 : 12,
        4,
        _isCollapsed ? 8 : 12,
        4,
      ),
      child: Material(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _toggleCollapsed,
          child: SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedRotation(
                  turns: _isCollapsed ? 0.5 : 0,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeInOutCubic,
                  child: const Icon(
                    Icons.chevron_left,
                    color: Colors.white70,
                    size: 24,
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _isCollapsed
                      ? const SizedBox.shrink(
                          key: ValueKey('collapse-label-off'),
                        )
                      : Padding(
                          key: ValueKey('collapse-label-on'),
                          padding: EdgeInsetsDirectional.only(start: 8),
                          child: Text(
                            s.tr('تصغير القائمة', 'Collapse menu'),
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
