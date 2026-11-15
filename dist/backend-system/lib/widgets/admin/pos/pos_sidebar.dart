import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/app_strings.dart';
import '../../../utils/admin_route_nav.dart';
import '../../language_toggle_button.dart';
import 'pos_menu_catalog.dart';

/// Collapsible right-side navigation for the cashier POS experience.
class PosSidebar extends StatefulWidget {
  const PosSidebar({
    super.key,
    required this.selectedRoute,
    required this.onRouteSelected,
    required this.onShiftCloseRequested,
    this.onPrinterSettings,
    this.onLogout,
    this.width = expandedWidth,
    this.enableCollapse = true,
    this.tableManagementEnabled = false,
  });

  static const double expandedWidth = 240;
  static const double collapsedWidth = 72;

  static const Color sidebarBg = Color(0xFF2C353F);
  static const Color activeBg = Color(0xFF6B1124);
  static const Color activeGold = Color(0xFFD49A00);

  static const _collapsedPrefKey = 'pos_sidebar_collapsed';

  final PosRoute selectedRoute;
  final ValueChanged<PosRoute> onRouteSelected;
  final VoidCallback onShiftCloseRequested;
  final VoidCallback? onPrinterSettings;
  final VoidCallback? onLogout;
  final double width;
  final bool enableCollapse;
  final bool tableManagementEnabled;

  @override
  State<PosSidebar> createState() => _PosSidebarState();
}

class _PosSidebarState extends State<PosSidebar> {
  var _collapsed = false;
  var _prefLoaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.enableCollapse) {
      _loadCollapsedPreference();
    } else {
      _prefLoaded = true;
    }
  }

  Future<void> _loadCollapsedPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _collapsed = prefs.getBool(PosSidebar._collapsedPrefKey) ?? false;
      _prefLoaded = true;
    });
  }

  Future<void> _toggleCollapsed() async {
    setState(() => _collapsed = !_collapsed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PosSidebar._collapsedPrefKey, _collapsed);
  }

  bool get _isCollapsed => widget.enableCollapse && _collapsed;

  double get _effectiveWidth =>
      _isCollapsed ? PosSidebar.collapsedWidth : widget.width;

  void _handleTap(PosSidebarMenuItem item) {
    switch (item.action) {
      case PosSidebarAction.openShiftCloseModal:
        widget.onShiftCloseRequested();
        return;
      case PosSidebarAction.openPrinterSettings:
        widget.onPrinterSettings?.call();
        return;
      case PosSidebarAction.logout:
        widget.onLogout?.call();
        return;
      case PosSidebarAction.navigate:
        widget.onRouteSelected(item.route);
        navigateToAdminPath(item.route.path);
    }
  }

  String _label(BuildContext context, PosSidebarMenuItem item) {
    final s = AppStrings.of(context);
    const labels = <String, String>{
      'pos_home': 'Point of Sale / Orders',
      'dine_in': 'Dining Tables',
      'online_orders': 'Online / Customer Orders',
      'driver_handoff': 'Driver Handoff / Delivery Payment',
      'printer_settings': 'Printer Settings',
      'close_shift': 'Close Shift',
      'logout': 'Log out',
      'shift_reports': 'Shift Reports',
      'void_orders': 'Void Orders',
      'manage_staff': 'Staff / Add Cashier',
      'manage_menu': 'Menu & Items',
    };
    return s.tr(item.label, labels[item.id] ?? item.label);
  }

  @override
  Widget build(BuildContext context) {
    if (!_prefLoaded && widget.enableCollapse) {
      return SizedBox(
        width: widget.width,
        child: const ColoredBox(
          color: PosSidebar.sidebarBg,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: PosSidebar.activeGold,
              ),
            ),
          ),
        ),
      );
    }

    final items = PosMenuCatalog.visibleItems(
      tableManagementEnabled: widget.tableManagementEnabled,
      showLogout: widget.onLogout != null,
    );

    return SizedBox(
      width: _effectiveWidth,
      child: ColoredBox(
      color: PosSidebar.sidebarBg,
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _isCollapsed
                              ? ''
                              : AppStrings.of(context).tr(
                                  'لا توجد أدوات متاحة',
                                  'No tools available',
                                ),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: _isCollapsed ? 8 : 10,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) =>
                          _buildNavItem(items[index]),
                    ),
            ),
            LanguageToggleButton(
              compact: _isCollapsed,
              foregroundColor: Colors.white,
            ),
            if (widget.enableCollapse) _buildCollapseToggle(),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: 20,
        horizontal: _isCollapsed ? 10 : 16,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: PosSidebar.activeGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.point_of_sale,
              color: PosSidebar.activeGold,
              size: 24,
            ),
          ),
          if (!_isCollapsed)
            const Padding(
              padding: EdgeInsetsDirectional.only(start: 10),
              child: Text(
                'POS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNavItem(PosSidebarMenuItem item) {
    final label = _label(context, item);
    final isActive =
        item.action == PosSidebarAction.navigate &&
        widget.selectedRoute == item.route;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isActive ? PosSidebar.activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _handleTap(item),
          child: Tooltip(
            message: _isCollapsed ? label : '',
            preferBelow: false,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _isCollapsed ? 0 : 12,
                vertical: 12,
              ),
              child: _isCollapsed
                  ? Center(
                      child: Icon(
                        item.icon,
                        color: isActive
                            ? PosSidebar.activeGold
                            : Colors.white70,
                        size: 22,
                      ),
                    )
                  : Row(
                      children: [
                        Icon(
                          item.icon,
                          color: isActive
                              ? PosSidebar.activeGold
                              : Colors.white70,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
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
                              fontSize: 13,
                              height: 1.25,
                            ),
                          ),
                        ),
                        if (isActive)
                          Container(
                            width: 4,
                            height: 18,
                            decoration: BoxDecoration(
                              color: PosSidebar.activeGold,
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

  Widget _buildCollapseToggle() {
    final s = AppStrings.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _isCollapsed ? 8 : 10,
        4,
        _isCollapsed ? 8 : 10,
        4,
      ),
      child: Material(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _toggleCollapsed,
          child: SizedBox(
            height: 38,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Transform.rotate(
                  angle: _isCollapsed ? 3.14159 : 0,
                  child: const Icon(
                    Icons.chevron_left,
                    color: Colors.white70,
                    size: 22,
                  ),
                ),
                if (!_isCollapsed)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 6),
                    child: Text(
                      s.tr('تصغير', 'Collapse'),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
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
