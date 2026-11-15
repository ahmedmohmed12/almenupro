import '../models/menu_item.dart';
import '../services/api_service.dart';

class AnalyticsSnapshot {
  const AnalyticsSnapshot({
    required this.todaySales,
    required this.lastWeekSales,
    required this.lastMonthSales,
    required this.topItems,
    required this.hourlyOrders,
    required this.dailyOrders,
    this.isDemo = false,
  });

  final double todaySales;
  final double lastWeekSales;
  final double lastMonthSales;
  final List<MapEntry<String, int>> topItems;
  final Map<String, int> hourlyOrders;
  final Map<String, int> dailyOrders;
  final bool isDemo;
}

/// Demo analytics shown when Firebase is not configured on web.
class AnalyticsDemoService {
  AnalyticsDemoService._();

  static Future<AnalyticsSnapshot> load() async {
    try {
      final items = await ApiService.instance.fetchMenuItems();
      if (items.isNotEmpty) {
        return _fromMenuItems(items);
      }
    } catch (_) {}

    return fallback();
  }

  static AnalyticsSnapshot fallback() {
    return AnalyticsSnapshot(
      todaySales: 42.5,
      lastWeekSales: 318.75,
      lastMonthSales: 1245,
      topItems: const [
        MapEntry('كوكيز نوتيلا', 28),
        MapEntry('مينى بايتس كيندر', 22),
        MapEntry('كوكيز شوكولاتة كيندر', 19),
        MapEntry('كوكيز Pistachio', 14),
        MapEntry('مينى بايتس ميكس', 11),
      ],
      hourlyOrders: const {
        '12:00': 4,
        '15:00': 7,
        '18:00': 12,
        '20:00': 18,
        '21:00': 15,
      },
      dailyOrders: const {
        'السبت': 18,
        'الأحد': 22,
        'الإثنين': 16,
        'الثلاثاء': 20,
        'الأربعاء': 19,
        'الخميس': 24,
        'الجمعة': 31,
      },
      isDemo: true,
    );
  }

  static AnalyticsSnapshot _fromMenuItems(List<MenuItem> items) {
    final sorted = [...items]..sort((a, b) => b.price.compareTo(a.price));
    final topItems = <MapEntry<String, int>>[];

    for (var i = 0; i < sorted.length && i < 6; i++) {
      final item = sorted[i];
      final qty = 24 - (i * 3);
      topItems.add(MapEntry(item.name, qty.clamp(4, 30)));
    }

    final avgPrice = items.fold<double>(0, (sum, item) => sum + item.price) /
        items.length;
    final todayOrders = topItems.fold<int>(0, (sum, entry) => sum + entry.value);

    return AnalyticsSnapshot(
      todaySales: (avgPrice * (todayOrders * 0.35)).clamp(8, 120),
      lastWeekSales: (avgPrice * todayOrders * 1.8).clamp(40, 900),
      lastMonthSales: (avgPrice * todayOrders * 6.5).clamp(150, 5000),
      topItems: topItems,
      hourlyOrders: const {
        '12:00': 5,
        '15:00': 8,
        '18:00': 14,
        '20:00': 19,
        '21:00': 16,
      },
      dailyOrders: const {
        'السبت': 20,
        'الأحد': 24,
        'الإثنين': 17,
        'الثلاثاء': 21,
        'الأربعاء': 18,
        'الخميس': 26,
        'الجمعة': 33,
      },
      isDemo: true,
    );
  }
}
