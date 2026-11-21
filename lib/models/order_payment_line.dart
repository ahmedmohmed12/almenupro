class OrderPaymentLine {
  const OrderPaymentLine({required this.method, required this.amount});

  final String method;
  final double amount;

  bool get isCash => method == 'cash';
  bool get isKnet => method == 'knet';

  factory OrderPaymentLine.fromMap(Map<String, dynamic> map) {
    final rawMethod =
        (map['method'] ?? map['payment_method'] ?? map['type'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    final method = _normalizeMethod(rawMethod);
    final amount = _parseAmount(map['amount'] ?? map['value']);
    return OrderPaymentLine(method: method, amount: amount);
  }

  Map<String, dynamic> toMap() => {'method': method, 'amount': amount};

  static String _normalizeMethod(String raw) {
    if (RegExp(r'cash|كاش').hasMatch(raw)) return 'cash';
    if (RegExp(r'k-?net|knet|كي\s*نت').hasMatch(raw)) return 'knet';
    return raw;
  }

  static double _parseAmount(Object? raw) {
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
    if (value == null || !value.isFinite) return 0;
    return double.parse(value.toStringAsFixed(3));
  }
}