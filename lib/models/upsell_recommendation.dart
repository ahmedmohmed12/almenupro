import 'menu_item.dart';

enum UpsellReason {
  linked,
  complement,
  popularPair,
  popular,
  freeDelivery,
  impulse,
  adminPick,
}

class UpsellRecommendation {
  const UpsellRecommendation({
    required this.item,
    required this.reason,
    this.score = 0,
  });

  final MenuItem item;
  final UpsellReason reason;
  final double score;

  String reasonLabel(String localeCode) {
    final isArabic = localeCode.startsWith('ar');
    switch (reason) {
      case UpsellReason.linked:
        return isArabic ? 'مع طلبك' : 'Goes with your order';
      case UpsellReason.complement:
        return isArabic ? 'يكمل طلبك' : 'Perfect pairing';
      case UpsellReason.popularPair:
        return isArabic ? 'يُطلب معاً' : 'Often ordered together';
      case UpsellReason.popular:
        return isArabic ? 'الأكثر طلباً' : 'Popular choice';
      case UpsellReason.freeDelivery:
        return isArabic ? 'توصيل مجاني' : 'Free delivery';
      case UpsellReason.impulse:
        return isArabic ? 'إضافة سريعة' : 'Quick add';
      case UpsellReason.adminPick:
        return isArabic ? 'مختار لك' : 'Staff pick';
    }
  }

  factory UpsellRecommendation.fromJson(
    Map<String, dynamic> json,
    MenuItem item,
  ) {
    final reasonRaw = json['reason']?.toString() ?? 'suggested';
    return UpsellRecommendation(
      item: item,
      reason: _parseReason(reasonRaw),
      score: (json['score'] as num?)?.toDouble() ?? 0,
    );
  }

  static UpsellReason _parseReason(String raw) {
    switch (raw) {
      case 'linked':
        return UpsellReason.linked;
      case 'complement':
        return UpsellReason.complement;
      case 'popular_pair':
        return UpsellReason.popularPair;
      case 'popular':
        return UpsellReason.popular;
      case 'free_delivery':
        return UpsellReason.freeDelivery;
      case 'admin_pick':
        return UpsellReason.adminPick;
      case 'impulse':
        return UpsellReason.impulse;
      default:
        return UpsellReason.popular;
    }
  }
}
