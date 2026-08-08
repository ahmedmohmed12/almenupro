enum CashbackType {
  percentage,
  fixedAmount;

  static CashbackType fromStorage(String? raw) {
    final value = (raw ?? 'PERCENTAGE').trim().toUpperCase();
    if (value == 'FIXED_AMOUNT' || value == 'FIXED') {
      return CashbackType.fixedAmount;
    }
    return CashbackType.percentage;
  }

  String get storageValue => switch (this) {
        CashbackType.percentage => 'PERCENTAGE',
        CashbackType.fixedAmount => 'FIXED_AMOUNT',
      };

  String get labelAr => switch (this) {
        CashbackType.percentage => 'نسبة مئوية (%)',
        CashbackType.fixedAmount => 'مبلغ ثابت (KWD)',
      };
}

class LoyaltyCashbackPreview {
  const LoyaltyCashbackPreview({
    required this.earnedCashback,
    required this.qualifies,
    required this.orderTotal,
    required this.cashbackType,
    required this.cashbackValue,
    required this.minOrderForLoyalty,
    this.reason,
  });

  final double earnedCashback;
  final bool qualifies;
  final double orderTotal;
  final CashbackType cashbackType;
  final double cashbackValue;
  final double minOrderForLoyalty;
  final String? reason;

  factory LoyaltyCashbackPreview.fromMap(Map<String, dynamic> map) {
    return LoyaltyCashbackPreview(
      earnedCashback: (map['earnedCashback'] as num?)?.toDouble() ?? 0,
      qualifies: map['qualifies'] == true,
      orderTotal: (map['orderTotal'] as num?)?.toDouble() ?? 0,
      cashbackType: CashbackType.fromStorage(
        map['cashbackType']?.toString() ?? map['cashback_type']?.toString(),
      ),
      cashbackValue: (map['cashbackValue'] as num?)?.toDouble() ??
          (map['cashback_value'] as num?)?.toDouble() ??
          0,
      minOrderForLoyalty: (map['minOrderForLoyalty'] as num?)?.toDouble() ??
          (map['min_order_for_loyalty'] as num?)?.toDouble() ??
          0,
      reason: map['reason']?.toString(),
    );
  }
}
