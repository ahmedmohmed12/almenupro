class OrderRatingLine {
  const OrderRatingLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String name;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  factory OrderRatingLine.fromJson(Map<String, dynamic> json) {
    return OrderRatingLine(
      name: json['name']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
      lineTotal: (json['lineTotal'] as num?)?.toDouble() ?? 0,
    );
  }
}

class OrderRatingPageData {
  const OrderRatingPageData({
    required this.orderId,
    required this.invoiceNumber,
    required this.createdAt,
    required this.paymentMethod,
    required this.totalPrice,
    required this.restaurantName,
    required this.items,
    required this.isRated,
    this.rating,
    this.reviewNote = '',
  });

  final String orderId;
  final String invoiceNumber;
  final DateTime? createdAt;
  final String paymentMethod;
  final double totalPrice;
  final String restaurantName;
  final List<OrderRatingLine> items;
  final bool isRated;
  final int? rating;
  final String reviewNote;

  String get displayNumber {
    final invoice = invoiceNumber.trim();
    if (invoice.isNotEmpty) return invoice;
    return orderId.replaceFirst(RegExp(r'^ord_'), '');
  }

  factory OrderRatingPageData.fromJson(Map<String, dynamic> json) {
    DateTime? created;
    final raw = json['createdAt']?.toString();
    if (raw != null && raw.isNotEmpty) {
      created = DateTime.tryParse(raw);
    }
    return OrderRatingPageData(
      orderId: json['orderId']?.toString() ?? '',
      invoiceNumber: json['invoiceNumber']?.toString() ?? '',
      createdAt: created,
      paymentMethod: json['paymentMethod']?.toString() ?? '',
      totalPrice: (json['totalPrice'] as num?)?.toDouble() ?? 0,
      restaurantName: json['restaurantName']?.toString() ?? '',
      items: (json['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((row) => OrderRatingLine.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      isRated: json['isRated'] == true,
      rating: (json['rating'] as num?)?.toInt(),
      reviewNote: json['reviewNote']?.toString() ?? '',
    );
  }
}
