import 'package:flutter/material.dart';

import 'admin_menu_panel.dart';

class AdminMenuSidebarFooter extends StatelessWidget {
  const AdminMenuSidebarFooter({
    super.key,
    required this.status,
    required this.collapsed,
  });

  final AdminMenuPanelStatus status;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: const Text(''), // يمكنك إضافة نص لاحقاً
    );
  }
}