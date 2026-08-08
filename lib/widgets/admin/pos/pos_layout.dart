import 'package:flutter/material.dart';

import 'pos_menu_catalog.dart';
import 'pos_sidebar.dart';

/// POS shell: main content + collapsible permission-based sidebar (RTL right edge).
class PosLayout extends StatelessWidget {
  const PosLayout({
    super.key,
    required this.selectedRoute,
    required this.onRouteSelected,
    required this.onShiftCloseRequested,
    required this.child,
    this.showSidebar = true,
  });

  final PosRoute selectedRoute;
  final ValueChanged<PosRoute> onRouteSelected;
  final VoidCallback onShiftCloseRequested;
  final Widget child;
  final bool showSidebar;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;

        if (!showSidebar || PosMenuCatalog.visibleItems().isEmpty) {
          return child;
        }

        if (compact) {
          return Scaffold(
            backgroundColor: const Color(0xFFF4F6F8),
            drawer: Drawer(
              width: PosSidebar.expandedWidth,
              backgroundColor: PosSidebar.sidebarBg,
              child: SafeArea(
                child: PosSidebar(
                  selectedRoute: selectedRoute,
                  onRouteSelected: onRouteSelected,
                  onShiftCloseRequested: onShiftCloseRequested,
                  enableCollapse: false,
                ),
              ),
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: const Color(0xFF6B1124),
                  child: Builder(
                    builder: (context) => IconButton(
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      icon: const Icon(Icons.menu, color: Colors.white),
                      tooltip: 'أدوات POS',
                    ),
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PosSidebar(
              selectedRoute: selectedRoute,
              onRouteSelected: onRouteSelected,
              onShiftCloseRequested: onShiftCloseRequested,
            ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}
