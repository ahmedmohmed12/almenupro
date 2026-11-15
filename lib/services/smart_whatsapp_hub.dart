import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/order.dart';
import 'whatsapp_broadcast.dart';

enum WhatsappStage { welcome, dispatch, review, retention }

class WhatsappTask {
  const WhatsappTask({
    required this.stage,
    required this.sentKey,
    required this.name,
    required this.phone,
    required this.orderId,
    required this.restaurantName,
    required this.ratingLink,
    required this.at,
  });

  final WhatsappStage stage;
  final String sentKey;
  final String name;
  final String phone;
  final String orderId;
  final String restaurantName;
  final String ratingLink;
  final DateTime at;
}

const whatsappStagePlaceholders = <String>[
  '{name}',
  '{restaurant_name}',
  '{order_id}',
  '{rating_link}',
  '{discount_code}',
];

const defaultWhatsappStageTemplates = <WhatsappStage, String>{
  WhatsappStage.welcome: '''مرحباً {name}
استلمنا طلبك رقم {order_id} في {restaurant_name}.
نجهّزه الآن وسنوافيك عند الخروج للتوصيل.''',
  WhatsappStage.dispatch: '''{name}، طلبك رقم {order_id} من {restaurant_name} خرج للتوصيل الآن.''',
  WhatsappStage.review: '''{name}، نتمنى أن طلب {order_id} من {restaurant_name} كان على الذوق.
لو تكرمت بتقييم 5 نجوم من هنا:
{rating_link}''',
  WhatsappStage.retention: '''اشتقنا لك {name} في {restaurant_name}.
استخدم الكود {discount_code} على طلبك القادم.''',
};

String whatsappStageLabel(WhatsappStage stage) {
  switch (stage) {
    case WhatsappStage.welcome:
      return 'ترحيب / استلام الطلب';
    case WhatsappStage.dispatch:
      return 'خرج للتوصيل';
    case WhatsappStage.review:
      return 'طلب تقييم 5 نجوم';
    case WhatsappStage.retention:
      return 'عرض العودة';
  }
}

String whatsappQueueLabel(WhatsappStage stage) {
  switch (stage) {
    case WhatsappStage.welcome:
      return 'طابور الترحيب';
    case WhatsappStage.dispatch:
      return 'طابور التوصيل';
    case WhatsappStage.review:
      return 'طابور التقييم';
    case WhatsappStage.retention:
      return 'طابور العودة';
  }
}

bool orderIsRefunded(Order order) {
  final blob = '${order.paymentMethod ?? ''} ${order.status.name} ${order.deliveryStatus ?? ''}'
      .toLowerCase();
  return blob.contains('refund') || blob.contains('مسترد') || blob.contains('مرتجع');
}

/// A late delivery should not be asked for a 5-star Talabat rating.
bool orderIsDelayed(Order order) {
  final status = (order.deliveryStatus ?? '').toLowerCase();
  if (status.contains('delay') || status.contains('late') || status.contains('متأخر')) {
    return true;
  }
  final deliveredAt = order.statusTimeline.deliveredAt;
  if (deliveredAt == null) return false;
  return deliveredAt.difference(order.createdAt) > const Duration(minutes: 75);
}

bool orderBlockedFromReview(Order order) {
  return order.status == OrderStatus.cancelled || orderIsRefunded(order) || orderIsDelayed(order);
}

String orderDisplayId(Order order) {
  final invoice = (order.invoiceNumber ?? '').trim();
  if (invoice.isNotEmpty) return invoice;
  final external = (order.externalOrderId ?? '').trim();
  if (external.isNotEmpty) return external;
  return order.id;
}

String ratingLinkForOrder(Order order) {
  final id = Uri.encodeComponent(order.id);
  final token = (order.ratingToken ?? '').trim();
  final query = token.isEmpty ? '' : '?token=${Uri.encodeComponent(token)}';
  return 'https://u-menus.com/order/$id/rate$query';
}

String renderWhatsappStage({
  required String template,
  required String name,
  required String restaurantName,
  required String orderId,
  required String ratingLink,
  required String discountCode,
}) {
  final safeName = name.trim().isEmpty ? 'عميلنا' : name.trim();
  final safeRestaurant = restaurantName.trim().isEmpty ? 'AlMenuPro' : restaurantName.trim();
  return template
      .replaceAll('{name}', safeName)
      .replaceAll('{restaurant_name}', safeRestaurant)
      .replaceAll('{order_id}', orderId)
      .replaceAll('{rating_link}', ratingLink)
      .replaceAll('{discount_code}', discountCode.trim().isEmpty ? 'ALMENU10' : discountCode.trim());
}

String renderTaskMessage({
  required String template,
  required WhatsappTask task,
  required String discountCode,
}) {
  return renderWhatsappStage(
    template: template,
    name: task.name,
    restaurantName: task.restaurantName,
    orderId: task.orderId,
    ratingLink: task.ratingLink,
    discountCode: discountCode,
  );
}

List<WhatsappTask> buildWhatsappTasks({
  required List<Order> orders,
  required String restaurantName,
  required DateTime now,
}) {
  final tasks = <WhatsappTask>[];
  final latestByPhone = <String, Order>{};

  for (final order in orders) {
    final phone = whatsAppBroadcastPhone(order.phone);
    if (phone == null) continue;
    final previous = latestByPhone[phone];
    if (previous == null || order.createdAt.isAfter(previous.createdAt)) {
      latestByPhone[phone] = order;
    }

    final name = order.customerName.trim().isEmpty ? 'عميلنا' : order.customerName.trim();
    final orderId = orderDisplayId(order);
    final link = ratingLinkForOrder(order);

    if ((order.status == OrderStatus.pending || order.status == OrderStatus.confirmed) &&
        now.difference(order.createdAt) <= const Duration(hours: 24)) {
      tasks.add(_task(WhatsappStage.welcome, order, phone, name, restaurantName, orderId, link));
    }

    final outForDelivery = order.orderType == OrderType.delivery &&
        (order.status == OrderStatus.preparing ||
            order.status == OrderStatus.ready ||
            order.isHeldByDriver) &&
        order.status != OrderStatus.cancelled &&
        order.status != OrderStatus.delivered;
    if (outForDelivery) {
      tasks.add(_task(WhatsappStage.dispatch, order, phone, name, restaurantName, orderId, link));
    }

    final completedAt = order.statusTimeline.deliveredAt ?? order.createdAt;
    if (order.status == OrderStatus.delivered &&
        !order.isRated &&
        !orderBlockedFromReview(order) &&
        now.difference(completedAt) >= const Duration(hours: 2)) {
      tasks.add(_task(WhatsappStage.review, order, phone, name, restaurantName, orderId, link));
    }
  }

  for (final order in latestByPhone.values) {
    if (order.status == OrderStatus.cancelled) continue;
    if (now.difference(order.createdAt) < const Duration(days: 3)) continue;
    final phone = whatsAppBroadcastPhone(order.phone);
    if (phone == null) continue;
    tasks.add(
      _task(
        WhatsappStage.retention,
        order,
        phone,
        order.customerName.trim().isEmpty ? 'عميلنا' : order.customerName.trim(),
        restaurantName,
        orderDisplayId(order),
        ratingLinkForOrder(order),
      ),
    );
  }

  tasks.sort((a, b) => b.at.compareTo(a.at));
  return tasks;
}

WhatsappTask _task(
  WhatsappStage stage,
  Order order,
  String phone,
  String name,
  String restaurantName,
  String orderId,
  String ratingLink,
) {
  final identity = stage == WhatsappStage.retention ? phone : order.id;
  return WhatsappTask(
    stage: stage,
    sentKey: '${stage.name}:$identity',
    name: name,
    phone: phone,
    orderId: orderId,
    restaurantName: restaurantName,
    ratingLink: ratingLink,
    at: order.createdAt,
  );
}

abstract class WhatsappHubStore {
  Future<Map<WhatsappStage, String>> loadTemplates();
  Future<void> saveTemplates(Map<WhatsappStage, String> templates);
  Future<String> loadDiscount();
  Future<void> saveDiscount(String code);
  Future<Set<String>> loadSent();
  Future<void> saveSent(Set<String> keys);
}

class MemoryWhatsappHubStore implements WhatsappHubStore {
  Map<WhatsappStage, String> templates = Map<WhatsappStage, String>.from(defaultWhatsappStageTemplates);
  String discount = 'ALMENU10';
  Set<String> sent = {};

  @override
  Future<String> loadDiscount() async => discount;

  @override
  Future<Set<String>> loadSent() async => Set<String>.of(sent);

  @override
  Future<Map<WhatsappStage, String>> loadTemplates() async =>
      Map<WhatsappStage, String>.from(templates);

  @override
  Future<void> saveDiscount(String code) async => discount = code;

  @override
  Future<void> saveSent(Set<String> keys) async => sent = Set<String>.of(keys);

  @override
  Future<void> saveTemplates(Map<WhatsappStage, String> value) async {
    templates = Map<WhatsappStage, String>.from(value);
  }
}

class SharedPrefsWhatsappHubStore implements WhatsappHubStore {
  static const templatesKey = 'smart_whatsapp_templates_v1';
  static const sentKey = 'smart_whatsapp_sent_v1';
  static const discountKey = 'smart_whatsapp_discount_v1';

  @override
  Future<Map<WhatsappStage, String>> loadTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(templatesKey);
    final stored = Map<WhatsappStage, String>.from(defaultWhatsappStageTemplates);
    if (raw == null || raw.isEmpty) return stored;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return stored;
      for (final stage in WhatsappStage.values) {
        final text = decoded[stage.name]?.toString();
        if (text != null && text.trim().isNotEmpty) stored[stage] = text;
      }
    } catch (_) {}
    return stored;
  }

  @override
  Future<void> saveTemplates(Map<WhatsappStage, String> templates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      templatesKey,
      jsonEncode({for (final stage in WhatsappStage.values) stage.name: templates[stage] ?? ''}),
    );
  }

  @override
  Future<String> loadDiscount() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(discountKey)?.trim() ?? '';
    return value.isEmpty ? 'ALMENU10' : value;
  }

  @override
  Future<void> saveDiscount(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(discountKey, code.trim());
  }

  @override
  Future<Set<String>> loadSent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(sentKey)?.toSet() ?? {};
  }

  @override
  Future<void> saveSent(Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(sentKey, keys.toList());
  }
}

class SmartWhatsappHubController extends ChangeNotifier {
  SmartWhatsappHubController({WhatsappHubStore? store}) : store = store ?? SharedPrefsWhatsappHubStore();

  final WhatsappHubStore store;
  Map<WhatsappStage, String> templates = Map<WhatsappStage, String>.from(defaultWhatsappStageTemplates);
  String discountCode = 'ALMENU10';
  final Set<String> sentKeys = {};
  List<WhatsappTask> tasks = const [];
  WhatsappStage stage = WhatsappStage.welcome;
  var ready = false;

  List<WhatsappTask> tasksFor(WhatsappStage value) =>
      tasks.where((task) => task.stage == value).toList();

  int pendingCount(WhatsappStage value) =>
      tasksFor(value).where((task) => !sentKeys.contains(task.sentKey)).length;

  bool isSent(WhatsappTask task) => sentKeys.contains(task.sentKey);

  Future<void> load(List<Order> orders, {required String restaurantName, DateTime? now}) async {
    templates = await store.loadTemplates();
    discountCode = await store.loadDiscount();
    sentKeys
      ..clear()
      ..addAll(await store.loadSent());
    tasks = buildWhatsappTasks(
      orders: orders,
      restaurantName: restaurantName,
      now: now ?? DateTime.now(),
    );
    ready = true;
    notifyListeners();
  }

  void selectStage(WhatsappStage value) {
    stage = value;
    notifyListeners();
  }

  Future<void> updateTemplate(WhatsappStage value, String text) async {
    templates[value] = text;
    notifyListeners();
    await store.saveTemplates(templates);
  }

  Future<void> updateDiscount(String code) async {
    discountCode = code.trim().isEmpty ? 'ALMENU10' : code.trim();
    notifyListeners();
    await store.saveDiscount(discountCode);
  }

  String messageFor(WhatsappTask task) {
    return renderTaskMessage(
      template: templates[task.stage] ?? '',
      task: task,
      discountCode: discountCode,
    );
  }

  String previewFor(WhatsappStage value) {
    return renderWhatsappStage(
      template: templates[value] ?? '',
      name: 'أحمد',
      restaurantName: 'دار السعد',
      orderId: '1042',
      ratingLink: 'https://u-menus.com/order/1042/rate',
      discountCode: discountCode,
    );
  }

  Future<void> markSent(WhatsappTask task) async {
    sentKeys.add(task.sentKey);
    notifyListeners();
    await store.saveSent(sentKeys);
  }
}
