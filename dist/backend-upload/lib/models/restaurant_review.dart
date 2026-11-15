class ReviewSummary {
  const ReviewSummary({
    this.average = 0,
    this.count = 0,
    this.distribution = const {},
  });

  final double average;
  final int count;
  final Map<int, int> distribution;

  bool get hasReviews => count > 0;

  factory ReviewSummary.fromJson(Map<String, dynamic> json) {
    final rawDist = json['distribution'];
    final dist = <int, int>{};
    if (rawDist is Map) {
      for (final entry in rawDist.entries) {
        final key = int.tryParse(entry.key.toString());
        final value = (entry.value as num?)?.toInt() ?? 0;
        if (key != null) dist[key] = value;
      }
    }
    return ReviewSummary(
      average: (json['average'] as num?)?.toDouble() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 0,
      distribution: dist,
    );
  }
}

class RestaurantReview {
  const RestaurantReview({
    required this.id,
    required this.rating,
    this.comment = '',
    this.customerName = '',
    this.phone = '',
    this.orderId,
    this.invoiceNumber = '',
    this.status = 'published',
    this.createdAt,
  });

  final String id;
  final int rating;
  final String comment;
  final String customerName;
  final String phone;
  final String? orderId;
  final String invoiceNumber;
  final String status;
  final DateTime? createdAt;

  bool get isHidden => status == 'hidden';

  factory RestaurantReview.fromJson(Map<String, dynamic> json) {
    return RestaurantReview(
      id: json['id']?.toString() ?? '',
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      comment: json['comment']?.toString() ?? '',
      customerName: json['customerName']?.toString() ??
          json['customer_name']?.toString() ??
          '',
      phone: json['phone']?.toString() ?? '',
      orderId: json['orderId']?.toString() ?? json['order_id']?.toString(),
      invoiceNumber: json['invoiceNumber']?.toString() ??
          json['invoice_number']?.toString() ??
          '',
      status: (json['status']?.toString() ?? 'published').toLowerCase(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }
}

class ReviewEligibility {
  const ReviewEligibility({
    required this.eligible,
    this.reason = '',
    this.status,
    this.orderId,
    this.invoiceNumber = '',
    this.customerName = '',
  });

  final bool eligible;
  final String reason;
  final String? status;
  final String? orderId;
  final String invoiceNumber;
  final String customerName;

  factory ReviewEligibility.fromJson(Map<String, dynamic> json) {
    return ReviewEligibility(
      eligible: json['eligible'] == true,
      reason: json['reason']?.toString() ?? '',
      status: json['status']?.toString(),
      orderId: json['orderId']?.toString() ?? json['order_id']?.toString(),
      invoiceNumber: json['invoiceNumber']?.toString() ??
          json['invoice_number']?.toString() ??
          '',
      customerName: json['customerName']?.toString() ??
          json['customer_name']?.toString() ??
          '',
    );
  }
}

class ReviewTrendPoint {
  const ReviewTrendPoint({
    required this.date,
    required this.count,
    required this.average,
  });

  final String date;
  final int count;
  final double average;

  factory ReviewTrendPoint.fromJson(Map<String, dynamic> json) {
    return ReviewTrendPoint(
      date: json['date']?.toString() ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
      average: (json['average'] as num?)?.toDouble() ?? 0,
    );
  }
}

class AdminReviewsPayload {
  const AdminReviewsPayload({
    required this.reviews,
    required this.summary,
    required this.trend,
  });

  final List<RestaurantReview> reviews;
  final ReviewSummary summary;
  final List<ReviewTrendPoint> trend;

  factory AdminReviewsPayload.fromJson(Map<String, dynamic> json) {
    final rawReviews = json['reviews'];
    final rawTrend = json['trend'];
    return AdminReviewsPayload(
      reviews: rawReviews is List
          ? rawReviews
              .whereType<Map>()
              .map((row) =>
                  RestaurantReview.fromJson(Map<String, dynamic>.from(row)))
              .toList()
          : const [],
      summary: json['summary'] is Map
          ? ReviewSummary.fromJson(Map<String, dynamic>.from(json['summary'] as Map))
          : const ReviewSummary(),
      trend: rawTrend is List
          ? rawTrend
              .whereType<Map>()
              .map((row) =>
                  ReviewTrendPoint.fromJson(Map<String, dynamic>.from(row)))
              .toList()
          : const [],
    );
  }
}
