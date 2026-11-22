class KitchenVoidLiability {
  const KitchenVoidLiability({
    required this.id,
    required this.restaurantId,
    required this.shiftId,
    required this.orderId,
    required this.cashierId,
    required this.cashierName,
    this.employeeId,
    required this.itemId,
    required this.itemName,
    required this.quantityRemoved,
    required this.amount,
    required this.reason,
    required this.approvalStatus,
    this.entityType,
    this.entityId,
    this.menuItemId,
    this.violationType,
    this.quantityBefore,
    this.quantityAfter,
    this.unitPrice,
    this.sentToKitchenAt,
    this.voidedAt,
    this.elapsedMinutes,
    this.reviewedById,
    this.reviewedByName,
    this.reviewNote,
    this.reviewedAt,
  });

  final String id;
  final String restaurantId;
  final String shiftId;
  final String orderId;
  final String? entityType;
  final String? entityId;
  final String cashierId;
  final String cashierName;
  final String? employeeId;
  final String itemId;
  final String? menuItemId;
  final String itemName;
  final String? violationType;
  final int? quantityBefore;
  final int? quantityAfter;
  final int quantityRemoved;
  final double? unitPrice;
  final double amount;
  final String? sentToKitchenAt;
  final String? voidedAt;
  final int? elapsedMinutes;
  final String reason;
  final String approvalStatus;
  final String? reviewedById;
  final String? reviewedByName;
  final String? reviewNote;
  final String? reviewedAt;
  final String? payrollDeductedAt;
  final int? payrollDeductedMonth;
  final int? payrollDeductedYear;

  bool get isPending => approvalStatus.toUpperCase() == 'PENDING';
  bool get isApproved => approvalStatus.toUpperCase() == 'APPROVED';
  bool get isRejected => approvalStatus.toUpperCase() == 'REJECTED';

  factory KitchenVoidLiability.fromJson(Map<String, dynamic> json) {
    double amount(String key, List<String> alt) {
      for (final k in [key, ...alt]) {
        final v = json[k];
        if (v is num) return v.toDouble();
      }
      return 0;
    }

    int asInt(String key, List<String> alt) {
      for (final k in [key, ...alt]) {
        final v = json[k];
        if (v is num) return v.toInt();
      }
      return 0;
    }

    return KitchenVoidLiability(
      id: json['id']?.toString() ?? '',
      restaurantId:
          (json['restaurantId'] ?? json['restaurant_id'] ?? '').toString(),
      shiftId: (json['shiftId'] ?? json['shift_id'] ?? '').toString(),
      orderId: (json['orderId'] ?? json['order_id'] ?? '').toString(),
      entityType: (json['entityType'] ?? json['entity_type'])?.toString(),
      entityId: (json['entityId'] ?? json['entity_id'])?.toString(),
      cashierId: (json['cashierId'] ?? json['cashier_id'] ?? '').toString(),
      cashierName: (json['cashierName'] ?? json['cashier_name'] ?? '').toString(),
      employeeId: (json['employeeId'] ?? json['employee_id'])?.toString(),
      itemId: (json['itemId'] ?? json['item_id'] ?? '').toString(),
      menuItemId: (json['menuItemId'] ?? json['menu_item_id'])?.toString(),
      itemName: (json['itemName'] ?? json['item_name'] ?? '').toString(),
      violationType: (json['violationType'] ?? json['violation_type'])?.toString(),
      quantityBefore: asInt('quantityBefore', const ['quantity_before']),
      quantityAfter: asInt('quantityAfter', const ['quantity_after']),
      quantityRemoved: asInt('quantityRemoved', const ['quantity_removed']),
      unitPrice: amount('unitPrice', const ['unit_price']),
      amount: amount('amount', const []),
      sentToKitchenAt:
          (json['sentToKitchenAt'] ?? json['sent_to_kitchen_at'])?.toString(),
      voidedAt: (json['voidedAt'] ?? json['voided_at'])?.toString(),
      elapsedMinutes: (json['elapsedMinutes'] ?? json['elapsed_minutes']) as int?,
      reason: (json['reason'] ?? '').toString(),
      approvalStatus: (json['approvalStatus'] ?? json['approval_status'] ?? 'PENDING')
          .toString(),
      reviewedById:
          (json['reviewedById'] ?? json['reviewed_by_id'])?.toString(),
      reviewedByName:
          (json['reviewedByName'] ?? json['reviewed_by_name'])?.toString(),
      reviewNote: (json['reviewNote'] ?? json['review_note'])?.toString(),
      reviewedAt: (json['reviewedAt'] ?? json['reviewed_at'])?.toString(),
      payrollDeductedAt:
          (json['payrollDeductedAt'] ?? json['payroll_deducted_at'])?.toString(),
      payrollDeductedMonth: json['payrollDeductedMonth'] is num
          ? (json['payrollDeductedMonth'] as num).toInt()
          : int.tryParse('${json['payroll_deducted_month'] ?? ''}'),
      payrollDeductedYear: json['payrollDeductedYear'] is num
          ? (json['payrollDeductedYear'] as num).toInt()
          : int.tryParse('${json['payroll_deducted_year'] ?? ''}'),
    );
  }
}

class KitchenVoidLiabilitySummary {
  const KitchenVoidLiabilitySummary({
    this.pendingCount = 0,
    this.pendingAmount = 0,
    this.approvedCount = 0,
    this.approvedAmount = 0,
    this.rejectedCount = 0,
    this.rejectedAmount = 0,
    this.cashierVoidDebt = 0,
    this.provisionalPendingCount = 0,
    this.provisionalPendingAmount = 0,
  });

  final int pendingCount;
  final double pendingAmount;
  final int approvedCount;
  final double approvedAmount;
  final int rejectedCount;
  final double rejectedAmount;
  final double cashierVoidDebt;
  final int provisionalPendingCount;
  final double provisionalPendingAmount;

  bool get hasPending => pendingCount > 0;
  bool get hasDebt => rejectedAmount > 0;

  factory KitchenVoidLiabilitySummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const KitchenVoidLiabilitySummary();
    double d(String key) => (json[key] as num?)?.toDouble() ?? 0;
    int i(String key) => (json[key] as num?)?.toInt() ?? 0;
    return KitchenVoidLiabilitySummary(
      pendingCount: i('pendingCount'),
      pendingAmount: d('pendingAmount'),
      approvedCount: i('approvedCount'),
      approvedAmount: d('approvedAmount'),
      rejectedCount: i('rejectedCount'),
      rejectedAmount: d('rejectedAmount'),
      cashierVoidDebt: d('cashierVoidDebt'),
      provisionalPendingCount: i('provisionalPendingCount'),
      provisionalPendingAmount: d('provisionalPendingAmount'),
    );
  }
}