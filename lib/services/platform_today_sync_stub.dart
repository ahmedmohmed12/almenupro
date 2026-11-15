class PlatformTodaySyncReport {
  const PlatformTodaySyncReport({
    required this.available,
    required this.platforms,
    required this.checked,
    required this.synced,
    required this.customersUpdated,
    required this.failed,
    required this.purged,
    this.details = const [],
  });

  const PlatformTodaySyncReport.unavailable()
    : available = false,
      platforms = 0,
      checked = 0,
      synced = 0,
      customersUpdated = 0,
      failed = 0,
      purged = 0,
      details = const [];

  final bool available;
  final int platforms;
  final int checked;
  final int synced;
  final int customersUpdated;
  final int failed;
  final int purged;
  final List<PlatformSyncDetail> details;
}

class PlatformSyncDetail {
  const PlatformSyncDetail({
    required this.provider,
    required this.checked,
    required this.synced,
    this.purged = 0,
    this.unread = false,
    this.alert = '',
    this.error = '',
    this.orderId = '',
    this.notice = '',
    this.background = false,
  });

  final String provider;
  final int checked;
  final int synced;
  final int purged;
  final bool unread;
  final String alert;
  final String error;
  final String orderId;
  final String notice;
  final bool background;
}

Future<PlatformTodaySyncReport> syncTodayPlatformSales() async {
  return const PlatformTodaySyncReport.unavailable();
}

void Function() listenPlatformSyncResult(
  void Function(PlatformSyncDetail detail) onResult,
) {
  return () {};
}

void Function() listenPlatformSyncAlert(
  void Function(PlatformSyncDetail detail) onAlert,
) {
  return () {};
}

void Function() listenPlatformSyncProgress(
  void Function(int checked, int synced) onProgress,
) {
  return () {};
}
