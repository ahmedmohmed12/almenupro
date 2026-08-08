import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/admin_route_nav.dart';
import 'pos_menu_catalog.dart';

/// Collapsible right-side navigation for the cashier POS experience.
class PosSidebar extends StatefulWidget {
  const PosSidebar({
    super.key,
    required this.selectedRoute,
    required this.onRouteSelected,
    required this.onShiftCloseRequested,
    this.width = expandedWidth,
    this.enableCollapse = true,
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
  final double width;
  final bool enableCollapse;

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
    if (item.action == PosSidebarAction.openShiftCloseModal) {
      widget.onShiftCloseRequested();
      return;
    }
    widget.onRouteSelected(item.route);
    navigateToAdminPath(item.route.path);
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

    final items = PosMenuCatalog.visibleItems();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      width: _effectiveWidth,
      color: PosSidebar.sidebarBg,
      clipBehavior: Clip.hardEdge,
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
                          _isCollapsed ? '' : 'لا توجد أدوات متاحة',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: _isCollapsed ? 8 : 10,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) => _buildNavItem(items[index]),
                    ),
            ),
            if (widget.enableCollapse) _buildCollapseToggle(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 260),
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
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _isCollapsed
                ? const SizedBox.shrink(key: ValueKey('pos-logo-collapsed'))
                : const Padding(
                    key: ValueKey('pos-logo-expanded'),
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
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(PosSidebarMenuItem item) {
    final isActive = item.action == PosSidebarAction.navigate &&
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
            message: _isCollapsed ? item.label : '',
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
                        color: isActive ? PosSidebar.activeGold : Colors.white70,
                        size: 22,
                      ),
                    )
                  : Row(
                      children: [
                        Icon(
                          item.icon,
                          color: isActive ? PosSidebar.activeGold : Colors.white70,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.white70,
                              fontWeight:
                                  isActive ? FontWeight.bold : FontWeight.w500,
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
                AnimatedRotation(
                  turns: _isCollapsed ? 0.5 : 0,
                  duration: const Duration(milliseconds: 260),
                  child: const Icon(
                    Icons.chevron_left,
                    color: Colors.white70,
                    size: 22,
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _isCollapsed
                      ? const SizedBox.shrink(key: ValueKey('pos-collapse-off'))
                      : const Padding(
                          key: ValueKey('pos-collapse-on'),
                          padding: EdgeInsetsDirectional.only(start: 6),
                          child: Text(
                            'تصغير',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
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
