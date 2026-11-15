class ShiftSummary {
  const ShiftSummary({
    this.orderCount = 0,
    this.voidCount = 0,
    this.refundCount = 0,
    this.cashSales = 0,
    this.knetSales = 0,
    this.electronicSales = 0,
    this.grossSales = 0,
    this.discountTotal = 0,
    this.refundTotal = 0,
    this.deliveryExpenses = 0,
    this.expectedCash = 0,
    this.actualCash = 0,
    this.discrepancy = 0,
    this.discrepancyType = 'balanced',
    this.dineInSales = 0,
    this.dineInCount = 0,
    this.takeawaySales = 0,
    this.takeawayCount = 0,
    this.deliverySales = 0,
    this.deliveryCount = 0,
    this.websiteSales = 0,
    this.websiteCount = 0,
    this.posSales = 0,
    this.posCount = 0,
  });

  final int orderCount;
  final int voidCount;
  final int refundCount;
  final double cashSales;
  final double knetSales;
  final double electronicSales;
  final double grossSales;
  final double discountTotal;
  final double refundTotal;
  final double deliveryExpenses;
  final double expectedCash;
  final double actualCash;
  final double discrepancy;
  final String discrepancyType;
  final double dineInSales;
  final int dineInCount;
  final double takeawaySales;
  final int takeawayCount;
  final double deliverySales;
  final int deliveryCount;
  final double websiteSales;
  final int websiteCount;
  final double posSales;
  final int posCount;

  String get discrepancyLabelAr => switch (discrepancyType) {
        'shortage' => 'عجز',
        'surplus' => 'فائض',
        _ => 'مطابق',
      };

  factory ShiftSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ShiftSummary();
    int asInt(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value is num) return value.toInt();
      }
      return 0;
    }

    double asDouble(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value is num) return value.toDouble();
      }
      return 0;
    }

    return ShiftSummary(
      orderCount: asInt(const ['orderCount', 'order_count']),
      voidCount: asInt(const ['voidCount', 'void_count']),
      refundCount: asInt(const ['refundCount', 'refund_count']),
      cashSales: asDouble(const ['cashSales', 'cash_sales']),
      knetSales: asDouble(const ['knetSales', 'knet_sales']),
      electronicSales: asDouble(const ['electronicSales', 'electronic_sales']),
      grossSales: asDouble(const ['grossSales', 'gross_sales']),
      discountTotal: asDouble(const ['discountTotal', 'discount_total']),
      refundTotal: asDouble(const ['refundTotal', 'refund_total']),
      deliveryExpenses: asDouble(const ['deliveryExpenses', 'delivery_expenses']),
      expectedCash: asDouble(const ['expectedCash', 'expected_cash']),
      actualCash: asDouble(const ['actualCash', 'actual_cash']),
      discrepancy: asDouble(const ['discrepancy']),
      discrepancyType:
          json['discrepancyType']?.toString() ??
          json['discrepancy_type']?.toString() ??
          'balanced',
      dineInSales: asDouble(const ['dineInSales', 'dine_in_sales']),
      dineInCount: asInt(const ['dineInCount', 'dine_in_count']),
      takeawaySales: asDouble(const ['takeawaySales', 'takeaway_sales']),
      takeawayCount: asInt(const ['takeawayCount', 'takeaway_count']),
      deliverySales: asDouble(const ['deliverySales', 'delivery_sales']),
      deliveryCount: asInt(const ['deliveryCount', 'delivery_count']),
      websiteSales: asDouble(const ['websiteSales', 'website_sales']),
      websiteCount: asInt(const ['websiteCount', 'website_count']),
      posSales: asDouble(const ['posSales', 'pos_sales']),
      posCount: asInt(const ['posCount', 'pos_count']),
    );
  }

  Map<String, dynamic> toJson() => {
        'orderCount': orderCount,
        'voidCount': voidCount,
        'refundCount': refundCount,
        'cashSales': cashSales,
        'knetSales': knetSales,
        'electronicSales': electronicSales,
        'grossSales': grossSales,
        'discountTotal': discountTotal,
        'refundTotal': refundTotal,
        'deliveryExpenses': deliveryExpenses,
        'expectedCash': expectedCash,
        'actualCash': actualCash,
        'discrepancy': discrepancy,
        'discrepancyType': discrepancyType,
        'dineInSales': dineInSales,
        'dineInCount': dineInCount,
        'takeawaySales': takeawaySales,
        'takeawayCount': takeawayCount,
        'deliverySales': deliverySales,
        'deliveryCount': deliveryCount,
        'websiteSales': websiteSales,
        'websiteCount': websiteCount,
        'posSales': posSales,
        'posCount': posCount,
      };
}

class ShiftSession {
  const ShiftSession({
    required this.id,
    required this.cashierId,
    required this.cashierName,
    required this.status,
    required this.openedAt,
    this.roleId = '',
    this.closedAt,
    this.openingFloat = 0,
    this.closingCashCounted,
    this.notes = '',
    this.summary = const ShiftSummary(),
    this.closedById,
    this.closedByName,
  });

  final String id;
  final String cashierId;
  final String cashierName;
  final String roleId;
  final String status;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingFloat;
  final double? closingCashCounted;
  final String notes;
  final ShiftSummary summary;
  final String? closedById;
  final String? closedByName;

  bool get isOpen => status.toLowerCase() == 'open';

  double get cashCollected =>
      closingCashCounted ?? summary.actualCash;

  factory ShiftSession.fromJson(Map<String, dynamic> json) {
    return ShiftSession(
      id: json['id']?.toString() ?? '',
      cashierId: json['cashierId']?.toString() ?? json['cashier_id']?.toString() ?? '',
      cashierName: json['cashierName']?.toString() ?? json['cashier_name']?.toString() ?? '',
      roleId: json['roleId']?.toString() ?? json['role_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'open',
      openedAt: DateTime.tryParse(json['openedAt']?.toString() ?? '') ?? DateTime.now().toUtc(),
      closedAt: DateTime.tryParse(json['closedAt']?.toString() ?? json['closed_at']?.toString() ?? ''),
      openingFloat: (json['openingFloat'] as num?)?.toDouble() ??
          (json['opening_float'] as num?)?.toDouble() ??
          0,
      closingCashCounted: json['closingCashCounted'] == null && json['closing_cash_counted'] == null
          ? null
          : (json['closingCashCounted'] as num?)?.toDouble() ??
              (json['closing_cash_counted'] as num?)?.toDouble(),
      notes: json['notes']?.toString() ?? '',
      summary: ShiftSummary.fromJson(
        json['summary'] is Map ? Map<String, dynamic>.from(json['summary'] as Map) : null,
      ),
      closedById: json['closedById']?.toString() ?? json['closed_by_id']?.toString(),
      closedByName: json['closedByName']?.toString() ?? json['closed_by_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'cashierId': cashierId,
        'cashierName': cashierName,
        'roleId': roleId,
        'status': status,
        'openedAt': openedAt.toUtc().toIso8601String(),
        if (closedAt != null) 'closedAt': closedAt!.toUtc().toIso8601String(),
        'openingFloat': openingFloat,
        if (closingCashCounted != null) 'closingCashCounted': closingCashCounted,
        'notes': notes,
        'summary': summary.toJson(),
        if (closedById != null) 'closedById': closedById,
        if (closedByName != null) 'closedByName': closedByName,
        'pettyCashLogs': const [],
        'registerBalance': openingFloat,
      };
}

class ShiftReportsMeta {
  const ShiftReportsMeta({
    this.totalShifts = 0,
    this.openShifts = 0,
    this.closedShifts = 0,
    this.grossSales = 0,
    this.dataState = '',
    this.openCount = 0,
    this.ordersInRange = 0,
    this.ordersWithoutShift = 0,
  });

  final int totalShifts;
  final int openShifts;
  final int closedShifts;
  final double grossSales;
  final String dataState;
  final int openCount;
  final int ordersInRange;
  final int ordersWithoutShift;

  factory ShiftReportsMeta.fromJson(Map<String, dynamic> json) {
    final openShifts = (json['openShifts'] as num?)?.toInt() ??
        (json['open_shifts'] as num?)?.toInt() ??
        (json['openCount'] as num?)?.toInt() ??
        0;
    return ShiftReportsMeta(
      totalShifts: (json['totalShifts'] as num?)?.toInt() ??
          (json['total_shifts'] as num?)?.toInt() ??
          0,
      openShifts: openShifts,
      closedShifts: (json['closedShifts'] as num?)?.toInt() ??
          (json['closed_shifts'] as num?)?.toInt() ??
          0,
      grossSales: (json['grossSales'] as num?)?.toDouble() ??
          (json['gross_sales'] as num?)?.toDouble() ??
          0,
      dataState: json['dataState']?.toString() ??
          json['data_state']?.toString() ??
          '',
      openCount: (json['openCount'] as num?)?.toInt() ??
          (json['open_count'] as num?)?.toInt() ??
          openShifts,
      ordersInRange: (json['ordersInRange'] as num?)?.toInt() ??
          (json['orders_in_range'] as num?)?.toInt() ??
          0,
      ordersWithoutShift: (json['ordersWithoutShift'] as num?)?.toInt() ??
          (json['orders_without_shift'] as num?)?.toInt() ??
          0,
    );
  }
}

class ShiftReportsResult {
  const ShiftReportsResult({
    this.shifts = const [],
    this.meta = const ShiftReportsMeta(),
  });

  final List<ShiftSession> shifts;
  final ShiftReportsMeta meta;

  List<ShiftSession> get openShifts =>
      shifts.where((shift) => shift.isOpen).toList();

  List<ShiftSession> get closedShifts =>
      shifts.where((shift) => !shift.isOpen).toList();
}
