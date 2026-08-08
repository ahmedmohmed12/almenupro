import 'package:flutter/material.dart';

import 'admin_restaurant_selector.dart';
import 'admin_breakpoints.dart';

class AdminTopHeader extends StatelessWidget {
  const AdminTopHeader({
    super.key,
    this.pendingOrdersCount = 0,
    this.onNotificationsTap,
    this.isSuperAdmin = false,
    this.showOrderNotifications = true,
    this.restaurantLabel,
    this.onMenuTap,
  });

  final int pendingOrdersCount;
  final VoidCallback? onNotificationsTap;
  final bool isSuperAdmin;
  final bool showOrderNotifications;
  final String? restaurantLabel;
  final VoidCallback? onMenuTap;

  static const Color burgundy = Color(0xFF6B1124);
  static const Color gold = Color(0xFFD49A00);

  String get _welcomeText {
    if (isSuperAdmin) return 'لوحة AlMenuPro — Super Admin';
    if (restaurantLabel != null && restaurantLabel!.trim().isNotEmpty) {
      return 'مرحباً بك، ${restaurantLabel!.trim()} 👋';
    }
    return 'مرحباً بك 👋';
  }

  @override
  Widget build(BuildContext context) {
    final mobile = AdminBreakpoints.isMobile(context);
    final horizontal = AdminBreakpoints.pagePadding(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(horizontal, mobile ? 10 : 16, horizontal, mobile ? 10 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: mobile ? _buildMobileLayout(context) : _buildDesktopLayout(context),
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _buildTitleBlock(compact: false)),
        if (isSuperAdmin) ...[
          const AdminRestaurantSelector(),
          const SizedBox(width: 16),
        ],
        ..._trailingActions(compact: false),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onMenuTap != null) ...[
              IconButton(
                tooltip: 'القائمة',
                onPressed: onMenuTap,
                icon: const Icon(Icons.menu, color: burgundy),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
            ],
            Expanded(child: _buildTitleBlock(compact: true)),
            ..._trailingActions(compact: true),
          ],
        ),
        if (isSuperAdmin) ...[
          const SizedBox(height: 10),
          const AdminRestaurantSelector(),
        ],
      ],
    );
  }

  Widget _buildTitleBlock({required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _welcomeText,
          maxLines: compact ? 3 : 2,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
          textAlign: TextAlign.start,
          style: TextStyle(
            fontSize: compact ? 16 : 20,
            fontWeight: FontWeight.bold,
            color: burgundy,
            height: 1.3,
          ),
        ),
        if (isSuperAdmin && !compact)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'اختر المطعم من القائمة لإدارة المنيو والإعدادات',
              style: TextStyle(fontSize: 13, color: Colors.black54),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  List<Widget> _trailingActions({required bool compact}) {
    return [
      if (showOrderNotifications) ...[
        IconButton(
          tooltip: 'الطلبات الجديدة',
          onPressed: onNotificationsTap,
          visualDensity: VisualDensity.compact,
          icon: Badge(
            isLabelVisible: pendingOrdersCount > 0,
            label: Text('$pendingOrdersCount'),
            backgroundColor: gold,
            child: Icon(
              Icons.notifications_outlined,
              color: burgundy,
              size: compact ? 24 : 28,
            ),
          ),
        ),
        if (!compact) const SizedBox(width: 8),
      ],
      CircleAvatar(
        radius: compact ? 18 : 22,
        backgroundColor: burgundy.withValues(alpha: 0.12),
        child: Icon(
          Icons.person,
          color: burgundy,
          size: compact ? 22 : 26,
        ),
      ),
    ];
  }
}
