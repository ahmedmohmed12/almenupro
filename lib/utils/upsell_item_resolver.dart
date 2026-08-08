import '../models/menu_item.dart';
import '../models/restaurant_settings.dart';
import '../models/upsell_recommendation.dart';

class UpsellItemResolver {
  static const _impulseKeywords = [
    'مشرو',
    'عصير',
    'قهو',
    'شاي',
    'صوص',
    'صلص',
    'sauce',
    'drink',
    'tea',
    'coffee',
    'حلو',
    'dessert',
    'cookie',
    'كوك',
  ];

  static const _complementRules = [
    _ComplementRule(
      cartKeywords: ['كوك', 'cookie', 'حلو', 'dessert', 'كيك', 'cake', 'براون'],
      suggestKeywords: ['مشرو', 'drink', 'coffee', 'tea', 'قهو', 'شاي', 'عصير'],
    ),
    _ComplementRule(
      cartKeywords: ['ساند', 'sandwich', 'burger', 'وجب', 'meal'],
      suggestKeywords: ['مشرو', 'drink', 'صوص', 'sauce', 'side', 'بطاط'],
    ),
  ];

  /// Cart-aware smart recommendations (Phase 2).
  static List<UpsellRecommendation> smartRecommendations({
    required List<MenuItem> allItems,
    required List<MenuItem> cartItems,
    required RestaurantSettings settings,
    required Set<int> cartItemIds,
    List<int> topItemIds = const [],
    double subtotal = 0,
    List<Map<String, dynamic>> serverHints = const [],
  }) {
    if (!settings.smartUpsellEnabled || !settings.smartRecommendationsEnabled) {
      return const [];
    }

    final itemById = {for (final item in allItems) item.id: item};
    final scores = <int, double>{};
    final reasons = <int, UpsellReason>{};

    void bump(int id, double amount, UpsellReason reason) {
      if (!itemById.containsKey(id) || cartItemIds.contains(id)) return;
      final item = itemById[id];
      if (item == null || !item.isAvailable) return;
      scores[id] = (scores[id] ?? 0) + amount;
      if (!reasons.containsKey(id) || amount >= 50) {
        reasons[id] = reason;
      }
    }

    for (final cartItem in cartItems) {
      for (final linkedId in cartItem.linkedItemIds) {
        bump(linkedId, 100, UpsellReason.linked);
      }
      for (final option in cartItem.options) {
        if (option.linkedMenuItemId != null) {
          bump(option.linkedMenuItemId!, 90, UpsellReason.linked);
        }
      }
    }

    for (final candidate in allItems) {
      if (!candidate.isAvailable || cartItemIds.contains(candidate.id)) continue;
      for (final rule in _complementRules) {
        final cartMatches =
            cartItems.any((item) => rule.matchesCart(item));
        if (cartMatches && rule.matchesSuggest(candidate)) {
          bump(candidate.id, 35, UpsellReason.complement);
        }
      }
    }

    for (final entry in serverHints) {
      final id = int.tryParse(entry['menuItemId']?.toString() ?? '');
      if (id == null) continue;
      final score = (entry['score'] as num?)?.toDouble() ?? 0;
      final reason = UpsellRecommendation.fromJson(
        {'reason': entry['reason']?.toString() ?? 'popular'},
        itemById[id] ?? _placeholderItem(id),
      ).reason;
      bump(id, score > 0 ? score : 12, reason);
    }

    for (var i = 0; i < topItemIds.length; i++) {
      bump(topItemIds[i], 8 + (topItemIds.length - i).toDouble(), UpsellReason.popular);
    }

    if (settings.hasFreeDeliveryGoal &&
        subtotal > 0 &&
        subtotal < settings.freeDeliveryThreshold) {
      final remaining = settings.freeDeliveryThreshold - subtotal;
      for (final candidate in allItems) {
        if (!candidate.isAvailable || candidate.price <= 0) continue;
        if (candidate.price >= remaining * 0.5 &&
            candidate.price <= remaining * 1.5) {
          bump(candidate.id, 45, UpsellReason.freeDelivery);
        }
      }
    }

    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ranked
        .take(6)
        .map(
          (entry) => UpsellRecommendation(
            item: itemById[entry.key]!,
            reason: reasons[entry.key] ?? UpsellReason.popular,
            score: entry.value,
          ),
        )
        .toList();
  }

  static List<UpsellRecommendation> impulseBumpRecommendations({
    required List<MenuItem> allItems,
    required RestaurantSettings settings,
    required Set<int> cartItemIds,
    Set<int> excludeIds = const {},
  }) {
    if (!settings.smartUpsellEnabled) return const [];

    Iterable<MenuItem> candidates;
    final adminPicked = settings.impulseBumpItemIds.isNotEmpty;

    if (adminPicked) {
      final idSet = settings.impulseBumpItemIds.toSet();
      candidates = allItems.where(
        (item) => idSet.contains(item.id) && item.isAvailable,
      );
    } else {
      candidates = allItems.where(
        (item) =>
            item.isAvailable &&
            item.price > 0 &&
            item.price <= settings.impulseBumpMaxPrice &&
            (_matchesImpulseKeyword(item) || item.price <= 1),
      );
    }

    return candidates
        .where(
          (item) =>
              !cartItemIds.contains(item.id) && !excludeIds.contains(item.id),
        )
        .take(8)
        .map(
          (item) => UpsellRecommendation(
            item: item,
            reason: adminPicked ? UpsellReason.adminPick : UpsellReason.impulse,
          ),
        )
        .toList();
  }

  /// Backward-compatible flat list for legacy callers.
  static List<MenuItem> impulseBumpItems({
    required List<MenuItem> allItems,
    required RestaurantSettings settings,
    required Set<int> cartItemIds,
  }) {
    return impulseBumpRecommendations(
      allItems: allItems,
      settings: settings,
      cartItemIds: cartItemIds,
    ).map((entry) => entry.item).toList();
  }

  static bool _matchesImpulseKeyword(MenuItem item) {
    final haystack =
        '${item.categoryName} ${item.name} ${item.nameAr} ${item.nameEn}'
            .toLowerCase();
    return _impulseKeywords.any((keyword) => haystack.contains(keyword));
  }

  static MenuItem _placeholderItem(int id) {
    return MenuItem(
      id: id,
      categoryId: 0,
      categoryName: '',
      name: '',
      description: '',
      price: 0,
      imageUrl: '',
      isAvailable: false,
    );
  }
}

class _ComplementRule {
  const _ComplementRule({
    required this.cartKeywords,
    required this.suggestKeywords,
  });

  final List<String> cartKeywords;
  final List<String> suggestKeywords;

  bool matchesCart(MenuItem item) => _matches(item, cartKeywords);

  bool matchesSuggest(MenuItem item) => _matches(item, suggestKeywords);

  bool _matches(MenuItem item, List<String> keywords) {
    final haystack =
        '${item.categoryName} ${item.name} ${item.nameAr} ${item.nameEn}'
            .toLowerCase();
    return keywords.any((keyword) => haystack.contains(keyword.toLowerCase()));
  }
}

/// Resolve linked side items for a single menu item (customization / item page).
List<MenuItem> resolveLinkedSideItems({
  required MenuItem item,
  required List<MenuItem> allItems,
  Set<int> cartItemIds = const {},
}) {
  final itemById = {for (final entry in allItems) entry.id: entry};
  final ids = <int>{
    ...item.linkedItemIds,
    ...item.options
        .map((option) => option.linkedMenuItemId)
        .whereType<int>(),
  };

  return ids
      .where((id) => !cartItemIds.contains(id))
      .map((id) => itemById[id])
      .whereType<MenuItem>()
      .where((entry) => entry.isAvailable)
      .toList();
}
