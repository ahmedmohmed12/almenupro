import 'dart:async';

import '../models/upsell_attribution.dart';
import '../models/upsell_recommendation.dart';
import 'api_service.dart';

/// Fire-and-forget upsell analytics (impressions + conversions).
class UpsellAnalyticsService {
  UpsellAnalyticsService._();

  static final UpsellAnalyticsService instance = UpsellAnalyticsService._();

  final Set<String> _loggedImpressionKeys = {};

  Future<void> logImpressions({
    required String surface,
    required List<UpsellRecommendation> recommendations,
    String? slug,
    String? restaurantId,
  }) async {
    if (recommendations.isEmpty) return;

    final events = <Map<String, dynamic>>[];
    for (final entry in recommendations) {
      final key = '$surface:${entry.item.id}';
      if (_loggedImpressionKeys.contains(key)) continue;
      _loggedImpressionKeys.add(key);
      events.add({
        'eventType': 'impression',
        'surface': surface,
        'menuItemId': entry.item.id,
        'itemName': entry.item.name,
        'reason': entry.reason.apiValue,
        'score': entry.score,
      });
    }

    if (events.isEmpty) return;
    unawaited(_postEvents(events, slug: slug, restaurantId: restaurantId));
  }

  Future<void> logConversion({
    required UpsellRecommendation recommendation,
    required String surface,
    required double revenue,
    String? slug,
    String? restaurantId,
  }) async {
    unawaited(
      _postEvents(
        [
          {
            'eventType': 'conversion',
            'surface': surface,
            'menuItemId': recommendation.item.id,
            'itemName': recommendation.item.name,
            'reason': recommendation.reason.apiValue,
            'score': recommendation.score,
            'revenue': revenue,
          },
        ],
        slug: slug,
        restaurantId: restaurantId,
      ),
    );
  }

  Future<void> logLinkedSideConversion({
    required int menuItemId,
    required String itemName,
    required double revenue,
    String? slug,
    String? restaurantId,
  }) async {
    unawaited(
      _postEvents(
        [
          {
            'eventType': 'conversion',
            'surface': 'linked_sides',
            'menuItemId': menuItemId,
            'itemName': itemName,
            'reason': 'linked',
            'revenue': revenue,
          },
        ],
        slug: slug,
        restaurantId: restaurantId,
      ),
    );
  }

  void resetSession() {
    _loggedImpressionKeys.clear();
  }

  Future<void> _postEvents(
    List<Map<String, dynamic>> events, {
    String? slug,
    String? restaurantId,
  }) async {
    try {
      await ApiService.instance.logUpsellEvents(
        events: events,
        slug: slug,
        restaurantId: restaurantId,
      );
    } catch (_) {
      // Analytics must never block checkout.
    }
  }
}
