import 'package:flutter/foundation.dart';

import '../models/customer.dart';
import '../models/order.dart';
import '../utils/whatsapp_phone.dart';
import 'admin_auth_service.dart';

/// Restaurant admins and super admins. Cashiers, kitchen, and drivers are excluded.
bool get canUseWhatsappBroadcast {
  final auth = AdminAuthService.instance;
  return auth.isRestaurantAdmin || auth.isSuperAdmin;
}

enum BroadcastPlatform { all, talabat, jahez, keeta, direct }

enum BroadcastRunState { idle, running, paused, cancelled, done }

enum BroadcastLogStatus { sent, failed, skipped }

class BroadcastRecipient {
  const BroadcastRecipient({
    required this.id,
    required this.name,
    required this.phone,
    required this.platform,
    required this.restaurantName,
    this.orderTimes = const [],
  });

  final String id;
  final String name;
  final String phone;
  final BroadcastPlatform platform;
  final String restaurantName;

  /// Creation times of this customer's orders. The campaign range matches any of them.
  final List<DateTime> orderTimes;

  String get platformLabel => broadcastPlatformLabel(platform);
}

enum BroadcastRangePreset { today, yesterday, last7Days, thisMonth }

class BroadcastDateRange {
  const BroadcastDateRange({this.from, this.to});

  final DateTime? from;
  final DateTime? to;
}

DateTime broadcastStartOfDay(DateTime value) {
  return value.isUtc
      ? DateTime.utc(value.year, value.month, value.day)
      : DateTime(value.year, value.month, value.day);
}

DateTime broadcastEndOfDay(DateTime value) {
  return broadcastStartOfDay(
    value,
  ).add(const Duration(days: 1)).subtract(const Duration(microseconds: 1));
}

BroadcastDateRange broadcastPresetRange(
  BroadcastRangePreset preset,
  DateTime now,
) {
  final today = broadcastStartOfDay(now);
  switch (preset) {
    case BroadcastRangePreset.today:
      return BroadcastDateRange(from: today, to: broadcastEndOfDay(now));
    case BroadcastRangePreset.yesterday:
      final day = today.subtract(const Duration(days: 1));
      return BroadcastDateRange(from: day, to: broadcastEndOfDay(day));
    case BroadcastRangePreset.last7Days:
      return BroadcastDateRange(
        from: today.subtract(const Duration(days: 6)),
        to: broadcastEndOfDay(now),
      );
    case BroadcastRangePreset.thisMonth:
      final start = now.isUtc
          ? DateTime.utc(now.year, now.month, 1)
          : DateTime(now.year, now.month, 1);
      return BroadcastDateRange(
        from: start,
        to: broadcastEndOfDay(_lastDayOfMonth(now)),
      );
  }
}

DateTime _lastDayOfMonth(DateTime value) {
  final nextMonth = value.month == 12
      ? (value.isUtc
            ? DateTime.utc(value.year + 1, 1, 1)
            : DateTime(value.year + 1, 1, 1))
      : (value.isUtc
            ? DateTime.utc(value.year, value.month + 1, 1)
            : DateTime(value.year, value.month + 1, 1));
  return nextMonth.subtract(const Duration(days: 1));
}

/// A customer stays in the campaign when any order was created inside the window.
bool broadcastOrderInRange(
  BroadcastRecipient recipient,
  DateTime? from,
  DateTime? to,
) {
  if (from == null && to == null) return true;
  return recipient.orderTimes.any((created) {
    if (from != null && created.isBefore(from)) return false;
    if (to != null && created.isAfter(to)) return false;
    return true;
  });
}

class BroadcastLogEntry {
  const BroadcastLogEntry({
    required this.at,
    required this.recipientName,
    required this.phone,
    required this.status,
    required this.detail,
  });

  final DateTime at;
  final String recipientName;
  final String phone;
  final BroadcastLogStatus status;
  final String detail;
}

const broadcastPlaceholders = <String>[
  '{name}',
  '{phone}',
  '{platform}',
  '{restaurant_name}',
];

const defaultBroadcastTemplate = '''مرحباً {name}
يسعدنا في {restaurant_name} أن نقدّم لك عرض AlMenuPro:

• Menu Engineering — ترتيب المنيو حسب الأرباح والأصناف الأقوى
• 5-Star Talabat Rating Strategy — خطة تقييم خمس نجوم على طلبات
• AlMenuPro POS System — نقطة البيع وإدارة الطلبات من شاشة واحدة

منصتك لدينا: {platform}
للتواصل على الرقم: {phone}''';

String broadcastPlatformLabel(BroadcastPlatform platform) {
  switch (platform) {
    case BroadcastPlatform.all:
      return 'كل المنصات';
    case BroadcastPlatform.talabat:
      return 'طلبات';
    case BroadcastPlatform.jahez:
      return 'جاهز';
    case BroadcastPlatform.keeta:
      return 'كيتا';
    case BroadcastPlatform.direct:
      return 'توصيل مباشر';
  }
}

BroadcastPlatform classifyBroadcastPlatform(String? source) {
  final value = (source ?? '').trim().toLowerCase();
  if (value.contains('talabat')) return BroadcastPlatform.talabat;
  if (value.contains('jahez')) return BroadcastPlatform.jahez;
  if (value.contains('keeta') || value.contains('keta')) {
    return BroadcastPlatform.keeta;
  }
  return BroadcastPlatform.direct;
}

/// Kuwait local numbers (8 digits) are sent with the 965 country code.
String? whatsAppBroadcastPhone(String raw) {
  var digits = WhatsAppPhone.digitsOnly(raw);
  if (digits.isEmpty) return null;
  if (digits.length == 8) digits = '965$digits';
  if (digits.length < 10 || digits.length > 15) return null;
  return digits;
}

String renderBroadcastTemplate(String template, BroadcastRecipient recipient) {
  return template
      .replaceAll(
        '{name}',
        recipient.name.trim().isEmpty ? 'عميلنا' : recipient.name.trim(),
      )
      .replaceAll('{phone}', recipient.phone)
      .replaceAll('{platform}', recipient.platformLabel)
      .replaceAll(
        '{restaurant_name}',
        recipient.restaurantName.trim().isEmpty
            ? 'AlMenuPro'
            : recipient.restaurantName.trim(),
      );
}

String insertBroadcastPlaceholder(String text, int offset, String token) {
  final safeOffset = offset.clamp(0, text.length);
  return text.replaceRange(safeOffset, safeOffset, token);
}

List<BroadcastRecipient> buildBroadcastAudience({
  required List<Customer> customers,
  required List<Order> orders,
  required String restaurantName,
}) {
  final platformByPhone = <String, BroadcastPlatform>{};
  final latestByPhone = <String, DateTime>{};
  final timesByPhone = <String, List<DateTime>>{};
  for (final order in orders) {
    final phone = WhatsAppPhone.digitsOnly(order.phone);
    if (phone.length < 8) continue;
    final created = order.createdAt;
    timesByPhone.putIfAbsent(phone, () => []).add(created);
    final previous = latestByPhone[phone];
    if (previous != null && created.isBefore(previous)) continue;
    latestByPhone[phone] = created;
    platformByPhone[phone] = classifyBroadcastPlatform(order.orderSource);
  }

  final seen = <String>{};
  final audience = <BroadcastRecipient>[];
  for (final customer in customers) {
    final phone = WhatsAppPhone.digitsOnly(customer.phone);
    if (phone.length < 8 || !seen.add(phone)) continue;
    audience.add(
      BroadcastRecipient(
        id: customer.id.isEmpty ? phone : customer.id,
        name: customer.customerName.trim().isEmpty
            ? 'عميل'
            : customer.customerName.trim(),
        phone: phone,
        platform: platformByPhone[phone] ?? BroadcastPlatform.direct,
        restaurantName: restaurantName,
        orderTimes: List<DateTime>.unmodifiable(
          timesByPhone[phone] ?? const [],
        ),
      ),
    );
  }
  audience.sort((a, b) => a.name.compareTo(b.name));
  return audience;
}

class WhatsappBroadcastController extends ChangeNotifier {
  WhatsappBroadcastController({
    List<BroadcastRecipient> audience = const [],
    this.delaySeconds = 2.5,
    String? template,
  }) : template = template ?? defaultBroadcastTemplate {
    _audience = List<BroadcastRecipient>.of(audience);
  }

  List<BroadcastRecipient> _audience = const [];
  final Set<String> _selectedIds = {};
  String query = '';
  BroadcastPlatform platform = BroadcastPlatform.all;
  DateTime? rangeFrom;
  DateTime? rangeTo;
  BroadcastRangePreset? activePreset;
  double delaySeconds;
  String template;
  BroadcastRunState runState = BroadcastRunState.idle;
  int sentCount = 0;
  int runTotal = 0;
  String currentName = '';
  final List<BroadcastLogEntry> logs = [];

  static const double minDelaySeconds = 1.5;
  static const double maxDelaySeconds = 5;

  List<BroadcastRecipient> get audience => List.unmodifiable(_audience);

  List<BroadcastRecipient> get visible {
    final needle = query.trim().toLowerCase();
    return _audience.where((recipient) {
      if (platform != BroadcastPlatform.all && recipient.platform != platform) {
        return false;
      }
      if (!broadcastOrderInRange(recipient, rangeFrom, rangeTo)) return false;
      if (needle.isEmpty) return true;
      final haystack =
          '${recipient.name} ${recipient.phone} ${recipient.restaurantName} ${recipient.platformLabel}'
              .toLowerCase();
      return haystack.contains(needle);
    }).toList();
  }

  List<BroadcastRecipient> get targets => visible
      .where((recipient) => _selectedIds.contains(recipient.id))
      .toList();

  int get audienceCount => targets.length;

  bool isSelected(String id) => _selectedIds.contains(id);

  bool get isRunning =>
      runState == BroadcastRunState.running ||
      runState == BroadcastRunState.paused;

  void replaceAudience(List<BroadcastRecipient> next) {
    _audience = List<BroadcastRecipient>.of(next);
    _selectedIds.removeWhere(
      (id) => _audience.every((recipient) => recipient.id != id),
    );
    notifyListeners();
  }

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  void setPlatform(BroadcastPlatform value) {
    platform = value;
    notifyListeners();
  }

  void setDateRange(DateTime? from, DateTime? to) {
    if (from != null && to != null && from.isAfter(to)) {
      rangeFrom = to;
      rangeTo = from;
    } else {
      rangeFrom = from;
      rangeTo = to;
    }
    activePreset = null;
    notifyListeners();
  }

  void applyDatePreset(BroadcastRangePreset preset, {DateTime? now}) {
    final range = broadcastPresetRange(preset, now ?? DateTime.now());
    rangeFrom = range.from;
    rangeTo = range.to;
    activePreset = preset;
    notifyListeners();
  }

  void clearDateRange() {
    rangeFrom = null;
    rangeTo = null;
    activePreset = null;
    notifyListeners();
  }

  void setDelay(double seconds) {
    delaySeconds = seconds.clamp(minDelaySeconds, maxDelaySeconds);
    notifyListeners();
  }

  void setTemplate(String value) {
    template = value;
    notifyListeners();
  }

  void toggle(String id) {
    if (!_selectedIds.add(id)) _selectedIds.remove(id);
    notifyListeners();
  }

  void selectAllVisible() {
    _selectedIds.addAll(visible.map((recipient) => recipient.id));
    notifyListeners();
  }

  void deselectAllVisible() {
    _selectedIds.removeAll(visible.map((recipient) => recipient.id));
    notifyListeners();
  }

  void invertVisible() {
    for (final recipient in visible) {
      if (!_selectedIds.add(recipient.id)) _selectedIds.remove(recipient.id);
    }
    notifyListeners();
  }

  void pause() {
    if (runState == BroadcastRunState.running) {
      runState = BroadcastRunState.paused;
      notifyListeners();
    }
  }

  void resume() {
    if (runState == BroadcastRunState.paused) {
      runState = BroadcastRunState.running;
      notifyListeners();
    }
  }

  void cancel() {
    if (isRunning) {
      runState = BroadcastRunState.cancelled;
      notifyListeners();
    }
  }

  /// Opens one WhatsApp chat per selected client, waiting [delaySeconds] between sends.
  Future<void> run(
    Future<bool> Function(BroadcastRecipient recipient, String message)
    dispatch,
  ) async {
    if (isRunning) return;
    final batch = List<BroadcastRecipient>.of(targets);
    runTotal = batch.length;
    sentCount = 0;
    currentName = '';
    runState = BroadcastRunState.running;
    notifyListeners();

    for (var index = 0; index < batch.length; index += 1) {
      if (!await _waitWhilePaused()) break;
      final recipient = batch[index];
      currentName = recipient.restaurantName.trim().isEmpty
          ? recipient.name
          : recipient.restaurantName;
      sentCount = index + 1;
      notifyListeners();

      final message = renderBroadcastTemplate(template, recipient);
      final phone = whatsAppBroadcastPhone(recipient.phone);
      if (phone == null) {
        _log(recipient, BroadcastLogStatus.skipped, 'رقم غير صالح');
        continue;
      }
      try {
        final opened = await dispatch(
          BroadcastRecipient(
            id: recipient.id,
            name: recipient.name,
            phone: phone,
            platform: recipient.platform,
            restaurantName: recipient.restaurantName,
          ),
          message,
        );
        _log(
          recipient,
          opened ? BroadcastLogStatus.sent : BroadcastLogStatus.failed,
          opened ? 'تم فتح واتساب' : 'تعذر فتح واتساب',
        );
      } catch (error) {
        _log(recipient, BroadcastLogStatus.failed, error.toString());
      }

      if (index < batch.length - 1 && !await _waitDelay()) break;
    }

    if (runState != BroadcastRunState.cancelled) {
      runState = BroadcastRunState.done;
    }
    currentName = '';
    notifyListeners();
  }

  void _log(
    BroadcastRecipient recipient,
    BroadcastLogStatus status,
    String detail,
  ) {
    logs.insert(
      0,
      BroadcastLogEntry(
        at: DateTime.now(),
        recipientName: recipient.name,
        phone: recipient.phone,
        status: status,
        detail: detail,
      ),
    );
    if (logs.length > 200) logs.removeRange(200, logs.length);
    notifyListeners();
  }

  Future<bool> _waitWhilePaused() async {
    while (runState == BroadcastRunState.paused) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return runState == BroadcastRunState.running;
  }

  Future<bool> _waitDelay() async {
    final totalMs = (delaySeconds * 1000).round();
    var waited = 0;
    while (waited < totalMs) {
      if (!await _waitWhilePaused()) return false;
      final step = (totalMs - waited).clamp(0, 200);
      if (step == 0) break;
      await Future<void>.delayed(Duration(milliseconds: step));
      waited += step;
    }
    return runState == BroadcastRunState.running;
  }
}
