import 'upsell_recommendation.dart';

/// Tracks how a cart line was added via Smart Upsell.
class UpsellAttribution {
  const UpsellAttribution({
    required this.surface,
    required this.reason,
    this.score = 0,
  });

  /// smart_recommendations | impulse_bumps | linked_sides
  final String surface;
  final String reason;
  final double score;

  Map<String, dynamic> toMap() => {
        'addedViaUpsell': true,
        'upsellSurface': surface,
        'upsellReason': reason,
        if (score > 0) 'upsellScore': score,
      };

  factory UpsellAttribution.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const UpsellAttribution(surface: 'unknown', reason: 'unknown');
    }
    return UpsellAttribution(
      surface: map['upsellSurface']?.toString() ??
          map['upsell_surface']?.toString() ??
          'unknown',
      reason: map['upsellReason']?.toString() ??
          map['upsell_reason']?.toString() ??
          'unknown',
      score: (map['upsellScore'] as num?)?.toDouble() ??
          (map['upsell_score'] as num?)?.toDouble() ??
          0,
    );
  }
}

extension UpsellReasonApi on UpsellReason {
  String get apiValue {
    switch (this) {
      case UpsellReason.linked:
        return 'linked';
      case UpsellReason.complement:
        return 'complement';
      case UpsellReason.popularPair:
        return 'popular_pair';
      case UpsellReason.popular:
        return 'popular';
      case UpsellReason.freeDelivery:
        return 'free_delivery';
      case UpsellReason.impulse:
        return 'impulse';
      case UpsellReason.adminPick:
        return 'admin_pick';
    }
  }
}
