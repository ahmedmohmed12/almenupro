enum ManagerReportPeriod {
  live,
  lastHour,
  today,
  yesterday,
  last7Days,
  last30Days,
}

extension ManagerReportPeriodX on ManagerReportPeriod {
  String get label => switch (this) {
        ManagerReportPeriod.live => 'مباشر',
        ManagerReportPeriod.lastHour => 'آخر ساعة',
        ManagerReportPeriod.today => 'اليوم',
        ManagerReportPeriod.yesterday => 'اليوم السابق',
        ManagerReportPeriod.last7Days => 'آخر 7 أيام',
        ManagerReportPeriod.last30Days => 'آخر 30 يوم',
      };

  String get salesTitle => switch (this) {
        ManagerReportPeriod.live => 'صافي المبيعات الآن',
        ManagerReportPeriod.lastHour => 'صافي المبيعات آخر ساعة',
        ManagerReportPeriod.today => 'صافي المبيعات اليوم',
        ManagerReportPeriod.yesterday => 'صافي مبيعات أمس',
        ManagerReportPeriod.last7Days => 'صافي المبيعات آخر 7 أيام',
        ManagerReportPeriod.last30Days => 'صافي المبيعات آخر 30 يوم',
      };

  String get chartTitle => switch (this) {
        ManagerReportPeriod.lastHour => 'المبيعات كل 5 دقائق',
        ManagerReportPeriod.last7Days => 'المبيعات باليوم',
        ManagerReportPeriod.last30Days => 'المبيعات باليوم',
        _ => 'المبيعات بالساعة',
      };

  bool get isLive => this == ManagerReportPeriod.live;
}

class ManagerPeriodWindow {
  const ManagerPeriodWindow({
    required this.from,
    required this.to,
    required this.compareFrom,
    required this.compareTo,
    required this.bucketCount,
    required this.bucket,
  });

  final DateTime from;
  final DateTime to;
  final DateTime compareFrom;
  final DateTime compareTo;
  final int bucketCount;
  final ManagerChartBucket bucket;
}

enum ManagerChartBucket { fiveMinutes, hour, day }

ManagerPeriodWindow managerPeriodWindow(
  ManagerReportPeriod period,
  DateTime now,
) {
  final local = now.toLocal();
  final todayStart = DateTime(local.year, local.month, local.day);
  final todayEnd = todayStart.add(const Duration(days: 1));

  switch (period) {
    case ManagerReportPeriod.lastHour:
      final to = local;
      final from = to.subtract(const Duration(hours: 1));
      return ManagerPeriodWindow(
        from: from,
        to: to,
        compareFrom: from.subtract(const Duration(hours: 1)),
        compareTo: from,
        bucketCount: 12,
        bucket: ManagerChartBucket.fiveMinutes,
      );
    case ManagerReportPeriod.yesterday:
      final from = todayStart.subtract(const Duration(days: 1));
      return ManagerPeriodWindow(
        from: from,
        to: todayStart,
        compareFrom: from.subtract(const Duration(days: 1)),
        compareTo: from,
        bucketCount: 24,
        bucket: ManagerChartBucket.hour,
      );
    case ManagerReportPeriod.last7Days:
      final from = todayStart.subtract(const Duration(days: 6));
      return ManagerPeriodWindow(
        from: from,
        to: todayEnd,
        compareFrom: from.subtract(const Duration(days: 7)),
        compareTo: from,
        bucketCount: 7,
        bucket: ManagerChartBucket.day,
      );
    case ManagerReportPeriod.last30Days:
      final from = todayStart.subtract(const Duration(days: 29));
      return ManagerPeriodWindow(
        from: from,
        to: todayEnd,
        compareFrom: from.subtract(const Duration(days: 30)),
        compareTo: from,
        bucketCount: 30,
        bucket: ManagerChartBucket.day,
      );
    case ManagerReportPeriod.live:
    case ManagerReportPeriod.today:
      return ManagerPeriodWindow(
        from: todayStart,
        to: todayEnd,
        compareFrom: todayStart.subtract(const Duration(days: 7)),
        compareTo: todayStart.subtract(const Duration(days: 6)),
        bucketCount: 24,
        bucket: ManagerChartBucket.hour,
      );
  }
}

int managerBucketIndex(DateTime createdAt, ManagerPeriodWindow window) {
  final t = createdAt.toLocal();
  switch (window.bucket) {
    case ManagerChartBucket.fiveMinutes:
      final minutes = t.difference(window.from).inMinutes;
      return (minutes ~/ 5).clamp(0, window.bucketCount - 1);
    case ManagerChartBucket.hour:
      if (window.bucketCount == 24 &&
          window.to.difference(window.from).inHours <= 24) {
        return t.hour.clamp(0, 23);
      }
      return t.difference(window.from).inHours.clamp(0, window.bucketCount - 1);
    case ManagerChartBucket.day:
      return t
          .difference(DateTime(window.from.year, window.from.month, window.from.day))
          .inDays
          .clamp(0, window.bucketCount - 1);
  }
}

String managerBucketLabel(int index, ManagerPeriodWindow window) {
  switch (window.bucket) {
    case ManagerChartBucket.fiveMinutes:
      final at = window.from.add(Duration(minutes: index * 5));
      return '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    case ManagerChartBucket.hour:
      return '${index.toString().padLeft(2, '0')}:00';
    case ManagerChartBucket.day:
      final day = DateTime(window.from.year, window.from.month, window.from.day)
          .add(Duration(days: index));
      return '${day.day}/${day.month}';
  }
}

String managerComparisonLabel(ManagerReportPeriod period) {
  return switch (period) {
    ManagerReportPeriod.live ||
    ManagerReportPeriod.today =>
      'مقابل نفس اليوم الأسبوع الماضي',
    ManagerReportPeriod.lastHour => 'مقابل الساعة السابقة',
    ManagerReportPeriod.yesterday => 'مقابل اليوم الذي قبله',
    ManagerReportPeriod.last7Days => 'مقابل الـ 7 أيام السابقة',
    ManagerReportPeriod.last30Days => 'مقابل الـ 30 يوماً السابقة',
  };
}
