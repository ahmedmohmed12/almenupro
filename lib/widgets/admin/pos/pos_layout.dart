import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../../language_toggle_button.dart';
import 'pos_menu_catalog.dart';
import 'pos_sidebar.dart';
import 'pos_theme.dart';

/// POS shell: main content + collapsible permission-based sidebar (RTL right edge).
class PosLayout extends StatelessWidget {
  const PosLayout({
    super.key,
    required this.selectedRoute,
    required this.onRouteSelected,
    required this.onShiftCloseRequested,
    required this.child,
    this.onPrinterSettings,
    this.onLogout,
    this.showSidebar = true,
    this.tableManagementEnabled = false,
  });

  final PosRoute selectedRoute;
  final ValueChanged<PosRoute> onRouteSelected;
  final VoidCallback onShiftCloseRequested;
  final VoidCallback? onPrinterSettings;
  final VoidCallback? onLogout;
  final Widget child;
  final bool showSidebar;
  final bool tableManagementEnabled;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        pageTransitionsTheme: PosTheme.pageTransitions,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
      child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1100;

        final hasSidebarItems = PosMenuCatalog.visibleItems(
          tableManagementEnabled: tableManagementEnabled,
          showLogout: onLogout != null,
        ).isNotEmpty;

        if (!showSidebar || !hasSidebarItems) {
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
                  onPrinterSettings: onPrinterSettings,
                  onLogout: onLogout,
                  enableCollapse: false,
                  tableManagementEnabled: tableManagementEnabled,
                ),
              ),
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: const Color(0xFF6B1124),
                  child: Row(
                    children: [
                      Builder(
                        builder: (context) => IconButton(
                          onPressed: () => Scaffold.of(context).openDrawer(),
                          icon: const Icon(Icons.menu, color: Colors.white),
                          tooltip: AppStrings.of(
                            context,
                          ).tr('أدوات POS', 'POS tools'),
                        ),
                      ),
                      const Spacer(),
                      const LanguageToggleButton(
                        compact: true,
                        foregroundColor: Colors.white,
                      ),
                    ],
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
              onPrinterSettings: onPrinterSettings,
              onLogout: onLogout,
              tableManagementEnabled: tableManagementEnabled,
            ),
            Expanded(child: child),
          ],
        );
      },
    ),
    );
  }
}
