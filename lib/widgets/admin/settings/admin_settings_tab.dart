enum AdminSettingsTab {
  whatsapp('whatsapp', '💬 رقم الواتساب والربط', 'whatsapp'),
  store('store', '🏪 بيانات المحل والمعاينة', 'storefront'),
  loyalty('loyalty', '🎁 برنامج الولاء والكاش باك', 'loyalty'),
  email('email', '✉️ إشعارات الإيميل', 'email'),
  platforms('platforms', '🌐 إعدادات المنصات', 'platforms'),
  paymentMethods(
    'payment-methods',
    '💳 طرق الدفع',
    'payment_methods',
  ),
  roles('roles', '👥 الأدوار والصلاحيات', 'roles'),
  workingHours(
    'working-hours',
    '⏰ مواعيد العمل',
    'working_hours',
  ),
  audioNotifications(
    'audio-notifications',
    '🔔 إعدادات التنبيه الصوتي',
    'audio_notifications',
  );

  const AdminSettingsTab(this.id, this.labelAr, this.iconName);

  final String id;
  final String labelAr;
  final String iconName;

  String get routePath => '/admin/settings/$id';

  static const settingsBasePath = '/admin/settings';

  static AdminSettingsTab fromId(String? value) {
    if (value == null || value.isEmpty) return AdminSettingsTab.whatsapp;
    for (final tab in AdminSettingsTab.values) {
      if (tab.id == value) return tab;
    }
    return AdminSettingsTab.whatsapp;
  }

  static AdminSettingsTab? fromRoutePath(String? path) {
    if (path == null || path.isEmpty) return null;
    final normalized = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    if (normalized == settingsBasePath) return AdminSettingsTab.whatsapp;
    if (!normalized.startsWith('$settingsBasePath/')) return null;
    final segment = normalized.substring(settingsBasePath.length + 1);
    if (segment.contains('/')) return null;
    return fromId(segment);
  }

  static bool isSettingsRoute(String? path) {
    if (path == null || path.isEmpty) return false;
    final normalized = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    return normalized == settingsBasePath ||
        normalized.startsWith('$settingsBasePath/');
  }

  static List<AdminSettingsTab> sidebarItems({required bool isSuperAdmin}) {
    if (isSuperAdmin) {
      return AdminSettingsTab.values
          .where((tab) => tab != AdminSettingsTab.audioNotifications)
          .toList();
    }
    return AdminSettingsTab.values;
  }
}
