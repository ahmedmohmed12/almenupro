import '../models/menu_item.dart';
import '../models/restaurant_settings.dart';
import 'food_cost_utils.dart';

final _comboFamilyPattern = RegExp(
  r'combo|كومبو|عائلت|عائلي|family|تشارك|sharing|وجبه?\s*عائلي|meal\s*deal',
  caseSensitive: false,
);

enum MenuPaydayPhase { star, plowhorse, budget }

class PaydayCycleInfo {
  const PaydayCycleInfo({
    required this.paydayStartDay,
    required this.cycleDay,
    required this.cycleLength,
    required this.phase,
  });

  final int paydayStartDay;
  final int cycleDay;
  final int cycleLength;
  final MenuPaydayPhase phase;

  String get phaseLabelAr => switch (phase) {
        MenuPaydayPhase.star => 'فترة الصرف المرتفع (نجوم الربحية)',
        MenuPaydayPhase.plowhorse => 'منتصف الدورة (وجبات عائلية وكومبو)',
        MenuPaydayPhase.budget => 'نهاية الدورة (أصناف اقتصادية)',
      };
}

int clampPaydayStartDay(int? value) {
  final day = value ?? 1;
  if (day < 1) return 1;
  if (day > 31) return 31;
  return day;
}

DateTime _kuwaitCalendarDate(DateTime now) {
  return now.toUtc().add(const Duration(hours: 3));
}

int _daysInMonth(int year, int month) {
  return DateTime(year, month + 1, 0).day;
}

int _paydayOn(int year, int month, int paydayStartDay) {
  final last = _daysInMonth(year, month);
  return paydayStartDay < last ? paydayStartDay : last;
}

PaydayCycleInfo paydayCycleInfo({
  DateTime? now,
  int paydayStartDay = 1,
}) {
  final startDay = clampPaydayStartDay(paydayStartDay);
  final kuwait = _kuwaitCalendarDate(now ?? DateTime.now());
  final year = kuwait.year;
  final month = kuwait.month;
  final day = kuwait.day;
  final thisPayday = _paydayOn(year, month, startDay);
  final today = DateTime(year, month, day);
  late DateTime cycleStart;
  late DateTime nextPayday;
  if (!today.isBefore(DateTime(year, month, thisPayday))) {
    cycleStart = DateTime(year, month, thisPayday);
    final nextMonthDate = DateTime(year, month + 1, 1);
    nextPayday = DateTime(
      nextMonthDate.year,
      nextMonthDate.month,
      _paydayOn(nextMonthDate.year, nextMonthDate.month, startDay),
    );
  } else {
    final prevMonthDate = DateTime(year, month - 1, 1);
    cycleStart = DateTime(
      prevMonthDate.year,
      prevMonthDate.month,
      _paydayOn(prevMonthDate.year, prevMonthDate.month, startDay),
    );
    nextPayday = DateTime(year, month, thisPayday);
  }
  final cycleDay = today.difference(cycleStart).inDays + 1;
  final cycleLength = nextPayday.difference(cycleStart).inDays;
  final phase = cycleDay <= 10
      ? MenuPaydayPhase.star
      : cycleDay <= 20
          ? MenuPaydayPhase.plowhorse
          : MenuPaydayPhase.budget;
  return PaydayCycleInfo(
    paydayStartDay: startDay,
    cycleDay: cycleDay < 1 ? 1 : cycleDay,
    cycleLength: cycleLength < 1 ? 1 : cycleLength,
    phase: phase,
  );
}

bool isComboOrFamilyItem(MenuItem item) {
  final haystack = [
    item.name,
    item.nameAr,
    item.nameEn,
    item.categoryName,
    item.categoryNameEn,
  ].join(' ');
  return _comboFamilyPattern.hasMatch(haystack);
}

int _compareManual(MenuItem a, MenuItem b) {
  final order = a.displayOrder.compareTo(b.displayOrder);
  if (order != 0) return order;
  return a.id.compareTo(b.id);
}

int _quadrantRank(MenuPaydayPhase phase, MenuEngineeringQuadrant? quadrant) {
  const ranks = {
    MenuPaydayPhase.star: {
      MenuEngineeringQuadrant.star: 0,
      MenuEngineeringQuadrant.puzzle: 1,
      MenuEngineeringQuadrant.plowhorse: 2,
      MenuEngineeringQuadrant.dog: 3,
    },
    MenuPaydayPhase.plowhorse: {
      MenuEngineeringQuadrant.plowhorse: 0,
      MenuEngineeringQuadrant.star: 1,
      MenuEngineeringQuadrant.puzzle: 2,
      MenuEngineeringQuadrant.dog: 3,
    },
    MenuPaydayPhase.budget: {
      MenuEngineeringQuadrant.dog: 0,
      MenuEngineeringQuadrant.plowhorse: 1,
      MenuEngineeringQuadrant.puzzle: 2,
      MenuEngineeringQuadrant.star: 3,
    },
  };
  return ranks[phase]?[quadrant] ?? 9;
}

int _compareStar(MenuItem a, MenuItem b) {
  final rank = _quadrantRank(MenuPaydayPhase.star, a.engineeringQuadrant)
      .compareTo(_quadrantRank(MenuPaydayPhase.star, b.engineeringQuadrant));
  if (rank != 0) return rank;
  final marginA = FoodCostMetrics.fromPrices(
    sellingPrice: a.price,
    costPrice: a.costPrice,
  )?.profitMargin;
  final marginB = FoodCostMetrics.fromPrices(
    sellingPrice: b.price,
    costPrice: b.costPrice,
  )?.profitMargin;
  if (marginA != null && marginB != null && marginA != marginB) {
    return marginB.compareTo(marginA);
  }
  if (marginA != null && marginB == null) return -1;
  if (marginA == null && marginB != null) return 1;
  final price = b.price.compareTo(a.price);
  if (price != 0) return price;
  return _compareManual(a, b);
}

int _comparePlowhorse(MenuItem a, MenuItem b) {
  final rank = _quadrantRank(MenuPaydayPhase.plowhorse, a.engineeringQuadrant)
      .compareTo(
        _quadrantRank(MenuPaydayPhase.plowhorse, b.engineeringQuadrant),
      );
  if (rank != 0) return rank;
  final comboA = isComboOrFamilyItem(a) ? 0 : 1;
  final comboB = isComboOrFamilyItem(b) ? 0 : 1;
  if (comboA != comboB) return comboA.compareTo(comboB);
  final vol = (b.orderCount ?? 0).compareTo(a.orderCount ?? 0);
  if (vol != 0) return vol;
  return _compareManual(a, b);
}

int _compareBudget(MenuItem a, MenuItem b) {
  final rank = _quadrantRank(MenuPaydayPhase.budget, a.engineeringQuadrant)
      .compareTo(_quadrantRank(MenuPaydayPhase.budget, b.engineeringQuadrant));
  if (rank != 0) return rank;
  final price = a.price.compareTo(b.price);
  if (price != 0) return price;
  return _compareManual(a, b);
}

List<MenuItem> sortCatalogItems(
  Iterable<MenuItem> items, {
  RestaurantSettings? settings,
  DateTime? now,
}) {
  final list = items.toList();
  if (settings == null || !settings.dynamicMenuSortingEnabled) {
    list.sort(_compareManual);
    return list;
  }
  final cycle = paydayCycleInfo(
    now: now,
    paydayStartDay: settings.paydayStartDay,
  );
  switch (cycle.phase) {
    case MenuPaydayPhase.star:
      list.sort(_compareStar);
    case MenuPaydayPhase.plowhorse:
      list.sort(_comparePlowhorse);
    case MenuPaydayPhase.budget:
      list.sort(_compareBudget);
  }
  return list;
}
