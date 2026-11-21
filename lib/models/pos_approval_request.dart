class PosApprovalRequest {
  const PosApprovalRequest({
    required this.id,
    required this.restaurantId,
    required this.shiftId,
    required this.type,
    required this.status,
    required this.requestedById,
    required this.requestedByName,
    required this.reason,
    required this.payload,
    this.restaurantSlug,
    this.reviewedById,
    this.reviewedByName,
    this.reviewNote,
    this.createdAt,
    this.reviewedAt,
    this.expiresAt,
  });

  final String id;
  final String restaurantId;
  final String? restaurantSlug;
  final String shiftId;
  final String type;
  final String status;
  final String requestedById;
  final String requestedByName;
  final String reason;
  final Map<String, dynamic> payload;
  final String? reviewedById;
  final String? reviewedByName;
  final String? reviewNote;
  final String? createdAt;
  final String? reviewedAt;
  final String? expiresAt;

  bool get isPending => status.toUpperCase() == 'PENDING';
  bool get isApproved => status.toUpperCase() == 'APPROVED';
  bool get isRejected => status.toUpperCase() == 'REJECTED';
  bool get isExpired => status.toUpperCase() == 'EXPIRED';

  String get typeLabelAr {
    switch (type.toUpperCase()) {
      case 'VOID_SENT_ITEM':
        return 'تعديل/إلغاء صنف مُرسل للمطبخ';
      case 'CLOSE_SHIFT_PENDING_ORDERS':
        return 'إغلاق وردية مع طلبات معلّقة';
      default:
        return type;
    }
  }

  factory PosApprovalRequest.fromJson(Map<String, dynamic> json) {
    final payloadRaw = json['payload'];
    return PosApprovalRequest(
      id: json['id']?.toString() ?? '',
      restaurantId:
          (json['restaurantId'] ?? json['restaurant_id'] ?? '').toString(),
      restaurantSlug:
          (json['restaurantSlug'] ?? json['restaurant_slug'])?.toString(),
      shiftId: (json['shiftId'] ?? json['shift_id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      status: (json['status'] ?? 'PENDING').toString(),
      requestedById:
          (json['requestedById'] ?? json['requested_by_id'] ?? '').toString(),
      requestedByName: (json['requestedByName'] ??
              json['requested_by_name'] ??
              'Cashier')
          .toString(),
      reason: (json['reason'] ?? '').toString(),
      payload: payloadRaw is Map
          ? Map<String, dynamic>.from(payloadRaw)
          : const <String, dynamic>{},
      reviewedById:
          (json['reviewedById'] ?? json['reviewed_by_id'])?.toString(),
      reviewedByName:
          (json['reviewedByName'] ?? json['reviewed_by_name'])?.toString(),
      reviewNote: (json['reviewNote'] ?? json['review_note'])?.toString(),
      createdAt: (json['createdAt'] ?? json['created_at'])?.toString(),
      reviewedAt: (json['reviewedAt'] ?? json['reviewed_at'])?.toString(),
      expiresAt: (json['expiresAt'] ?? json['expires_at'])?.toString(),
    );
  }
}

abstract final class PosApprovalTypes {
  static const voidSentItem = 'VOID_SENT_ITEM';
  static const closeShiftPendingOrders = 'CLOSE_SHIFT_PENDING_ORDERS';
}