import 'dart:js_interop';
import 'dart:js_interop_unsafe';

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

int _readInt(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse('$value') ?? 0;
}

void Function() listenPlatformSyncResult(
  void Function(PlatformSyncDetail detail) onResult,
) {
  if (!globalContext.has('AlMenuProDesktop')) return () {};
  final bridge = globalContext.getProperty('AlMenuProDesktop'.toJS);
  if (bridge == null || bridge.isUndefined) return () {};
  void handle(JSAny? payload) {
    final raw = payload.dartify();
    if (raw is! Map) return;
    final map = Map<Object?, Object?>.from(raw);
    onResult(
      PlatformSyncDetail(
        provider: '${map['provider'] ?? ''}',
        checked: _readInt(map, 'checked'),
        synced: _readInt(map, 'synced'),
        purged: _readInt(map, 'purged'),
        unread: map['unread'] == true,
        alert: '${map['alert'] ?? ''}',
        error: '${map['error'] ?? ''}',
        orderId: '${map['orderId'] ?? ''}',
        notice: '${map['notice'] ?? ''}',
        background: map['background'] == true,
      ),
    );
  }

  final stop = (bridge as JSObject).callMethod(
    'onPlatformSync'.toJS,
    handle.toJS,
  );
  return () {
    if (stop is JSFunction) {
      stop.callAsFunction();
    }
  };
}

void Function() listenPlatformSyncAlert(
  void Function(PlatformSyncDetail detail) onAlert,
) {
  if (!globalContext.has('AlMenuProDesktop')) return () {};
  final bridge = globalContext.getProperty('AlMenuProDesktop'.toJS);
  if (bridge == null || bridge.isUndefined) return () {};
  void handle(JSAny? payload) {
    final raw = payload.dartify();
    if (raw is! Map) return;
    final map = Map<Object?, Object?>.from(raw);
    onAlert(
      PlatformSyncDetail(
        provider: '${map['provider'] ?? ''}',
        checked: 0,
        synced: 0,
        alert: '${map['alert'] ?? ''}',
        error: '${map['error'] ?? ''}',
        orderId: '${map['orderId'] ?? ''}',
      ),
    );
  }

  final stop = (bridge as JSObject).callMethod(
    'onSyncAlert'.toJS,
    handle.toJS,
  );
  return () {
    if (stop is JSFunction) {
      stop.callAsFunction();
    }
  };
}

void Function() listenPlatformSyncProgress(
  void Function(int checked, int synced) onProgress,
) {
  if (!globalContext.has('AlMenuProDesktop')) return () {};
  final bridge = globalContext.getProperty('AlMenuProDesktop'.toJS);
  if (bridge == null || bridge.isUndefined) return () {};
  void handle(JSAny? payload) {
    final raw = payload.dartify();
    if (raw is! Map) return;
    final map = Map<Object?, Object?>.from(raw);
    onProgress(_readInt(map, 'checked'), _readInt(map, 'synced'));
  }

  final stop = (bridge as JSObject).callMethod(
    'onSyncProgress'.toJS,
    handle.toJS,
  );
  return () {
    if (stop is JSFunction) {
      stop.callAsFunction();
    }
  };
}

Future<PlatformTodaySyncReport> syncTodayPlatformSales() async {
  if (!globalContext.has('AlMenuProDesktop')) {
    return const PlatformTodaySyncReport.unavailable();
  }
  final bridge = globalContext.getProperty('AlMenuProDesktop'.toJS);
  if (bridge == null || bridge.isUndefined) {
    return const PlatformTodaySyncReport.unavailable();
  }
  final result = (bridge as JSObject).callMethod('syncTodaySales'.toJS);
  if (result == null || result.isUndefined) {
    return const PlatformTodaySyncReport.unavailable();
  }
  final resolved = await (result as JSPromise).toDart;
  final raw = resolved.dartify();
  if (raw is! Map) {
    return const PlatformTodaySyncReport.unavailable();
  }
  final map = Map<Object?, Object?>.from(raw);
  final details = <PlatformSyncDetail>[];
  final rawDetails = map['details'];
  if (rawDetails is List) {
    for (final row in rawDetails) {
      if (row is! Map) continue;
      final item = Map<Object?, Object?>.from(row);
      details.add(
        PlatformSyncDetail(
          provider: '${item['provider'] ?? ''}',
          checked: _readInt(item, 'checked'),
          synced: _readInt(item, 'synced'),
          purged: _readInt(item, 'purged'),
          unread: item['unread'] == true,
        ),
      );
    }
  }
  return PlatformTodaySyncReport(
    available: true,
    platforms: _readInt(map, 'platforms'),
    checked: _readInt(map, 'checked'),
    synced: _readInt(map, 'synced'),
    customersUpdated: _readInt(map, 'customersUpdated'),
    failed: _readInt(map, 'failed'),
    purged: _readInt(map, 'purged'),
    details: details,
  );
}
